--[[
	职责：组装玩家存档载入、状态恢复、自动保存、离服保存和关服等待。
	输入：Start 无参数；SavePlayer 接收在线 player。
	输出：通过 PlayerDataReadyService 发布载入完成状态；SavePlayer 返回是否已排队。
	内部算法：先同步标记 Loading，再异步读取/迁移/应用；保存先同步快照，再按 UserId 合并排队。
	安全规则：读取/版本/应用失败时使用默认档运行，但整次会话禁止保存，避免覆盖有效云存档。
	不负责：业务状态计算、Plot/模型生成、攻击恢复或 UI。
]]

local Players = game:GetService("Players")

local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerDataStoreAccess = require(script.Parent.PlayerDataStoreAccess)
local PlayerPersistenceConfigs = require(script.Parent.PlayerPersistenceConfigs)
local PlayerSaveStateAdapter = require(script.Parent.PlayerSaveStateAdapter)
local PlayerSaveSchema = require(game:GetService("ReplicatedStorage").Shared.Persistence.PlayerSaveSchema)

local PlayerPersistenceCoordinator = {}

type QueueRecord = {
	Latest: any?,
	Running: boolean,
}

local queuesByUserId: { [number]: QueueRecord } = {}
local started = false
local closing = false

local function retry(operation, attempts: number)
	local lastResult = nil
	for attempt = 1, attempts do
		lastResult = operation()
		if lastResult.Succeeded then
			return lastResult
		end
		if attempt < attempts then
			task.wait(PlayerPersistenceConfigs.RetryDelaySeconds * attempt)
		end
	end
	return lastResult
end

local function loadPlayer(player: Player)
	local loaded = retry(function()
		return PlayerDataStoreAccess.Load(player.UserId)
	end, if PlayerDataStoreAccess.IsEnabled() then PlayerPersistenceConfigs.LoadAttempts else 1)
	if player.Parent ~= Players then
		PlayerDataReadyService.Cancel(player, "PlayerLeftDuringLoad")
		return
	end

	local data = nil
	local canSave = loaded.Succeeded
	local readyReason = loaded.Reason
	if loaded.Succeeded then
		data, readyReason = PlayerSaveSchema.Normalize(loaded.Value)
		if not data then
			canSave = false
		end
	end
	if not data then
		data = PlayerSaveSchema.Default()
	end

	local applied, applyFailure = pcall(PlayerSaveStateAdapter.Apply, player, data, os.time())
	if not applied then
		canSave = false
		readyReason = "StateApplyFailed"
		warn(string.format("玩家 %s 状态恢复失败：%s", player.Name, tostring(applyFailure)))
		-- 覆盖可能已经部分写入的字段，使后续系统至少看到一套完整默认状态。
		local fallbackApplied, fallbackFailure = pcall(
			PlayerSaveStateAdapter.Apply,
			player,
			PlayerSaveSchema.Default(),
			os.time()
		)
		if not fallbackApplied then
			warn(string.format("玩家 %s 默认状态恢复失败：%s", player.Name, tostring(fallbackFailure)))
		end
	elseif not loaded.Succeeded and loaded.Reason ~= "PersistenceDisabled" then
		warn(string.format("玩家 %s 存档读取失败，本次会话禁止保存：%s", player.Name, tostring(loaded.Reason)))
	end

	PlayerDataReadyService.MarkReady(player, canSave, readyReason)
end

local function beginLoad(player: Player)
	PlayerDataReadyService.MarkLoading(player)
	task.spawn(loadPlayer, player)
end

local function runSaveQueue(userId: number, record: QueueRecord)
	while record.Latest do
		local data = record.Latest
		record.Latest = nil
		local saved = retry(function()
			return PlayerDataStoreAccess.Save(userId, data)
		end, PlayerPersistenceConfigs.SaveAttempts)
		if not saved.Succeeded then
			warn(string.format("玩家 %d 存档保存失败：%s", userId, tostring(saved.Reason)))
		end
	end
	record.Running = false
	if record.Latest then
		record.Running = true
		task.spawn(runSaveQueue, userId, record)
	else
		queuesByUserId[userId] = nil
	end
end

local function queueSnapshot(userId: number, data)
	local record = queuesByUserId[userId]
	if not record then
		record = { Latest = nil, Running = false }
		queuesByUserId[userId] = record
	end
	record.Latest = data
	if not record.Running then
		record.Running = true
		task.spawn(runSaveQueue, userId, record)
	end
end

local function capture(player: Player)
	local captured, value = pcall(PlayerSaveStateAdapter.Capture, player, os.time())
	if not captured then
		return nil, "SnapshotFailed:" .. tostring(value)
	end
	local normalized, reason = PlayerSaveSchema.Normalize(value)
	if not normalized then
		return nil, reason or "SnapshotInvalid"
	end
	return normalized, nil
end

function PlayerPersistenceCoordinator.SavePlayer(player: Player): (boolean, string?)
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status ~= "Ready" then
		return false, "PlayerDataNotReady"
	end
	if not readiness.CanSave then
		return false, readiness.Reason or "SaveDisabledForSession"
	end
	local data, reason = capture(player)
	if not data then
		return false, reason
	end
	queueSnapshot(player.UserId, data)
	return true, nil
end

local function playerRemoving(player: Player)
	-- Capture 在任何 yield 之前完成，避免 PlayerStateService 删除状态树后再读取。
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status == "Ready" and readiness.CanSave then
		local data, reason = capture(player)
		if data then
			queueSnapshot(player.UserId, data)
		else
			warn(string.format("玩家 %s 离服快照失败：%s", player.Name, tostring(reason)))
		end
	end
	PlayerDataReadyService.Cancel(player, "PlayerLeaving")
end

local function autosaveLoop()
	while not closing do
		task.wait(PlayerPersistenceConfigs.AutosaveIntervalSeconds)
		if closing then
			break
		end
		for _, player in Players:GetPlayers() do
			local queued, reason = PlayerPersistenceCoordinator.SavePlayer(player)
			if not queued and reason and reason:sub(1, 14) == "SnapshotFailed" then
				warn(string.format("玩家 %s 自动保存快照失败：%s", player.Name, reason))
			end
		end
	end
end

local function bindToClose()
	closing = true
	for _, player in Players:GetPlayers() do
		PlayerPersistenceCoordinator.SavePlayer(player)
	end
	local deadline = os.clock() + PlayerPersistenceConfigs.ShutdownWaitSeconds
	while next(queuesByUserId) ~= nil and os.clock() < deadline do
		task.wait(0.1)
	end
end

function PlayerPersistenceCoordinator.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(beginLoad)
	Players.PlayerRemoving:Connect(playerRemoving)
	game:BindToClose(bindToClose)
	for _, player in Players:GetPlayers() do
		beginLoad(player)
	end
	task.spawn(autosaveLoop)
end

return PlayerPersistenceCoordinator
