--[[
	职责：组装玩家存档会话获取、状态恢复、自动保存、离服最终提交、Studio 删档和关服等待。
	输入：Start 无参数；SavePlayer/DeleteStudioSave 接收在线 player；CommitReplacement 额外接收完整新存档。
	输出：通过 PlayerDataReadyService 发布 Ready/Cancelled；保存和 Studio 删档返回结构化结果。
	内部算法：获取独占租约 → 应用存档 → 快照合并队列 → Revision 条件提交 → 最终提交释放租约。
	安全规则：加载/版本/应用失败或会话冲突时拒绝玩家进入；失败提交保留同一 CommitId 重试。
	不负责：业务状态计算、Plot/模型生成、攻击恢复、UI 或跨 Place 会话交接。
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerDataStoreAccess = require(script.Parent.PlayerDataStoreAccess)
local PlayerPersistenceConfigs = require(script.Parent.PlayerPersistenceConfigs)
local PlayerPersistenceDiagnostics = require(script.Parent.PlayerPersistenceDiagnostics)
local PlayerSaveStateAdapter = require(script.Parent.PlayerSaveStateAdapter)
local StudioTestSessionPolicy = require(script.Parent.StudioTestSessionPolicy)
local PlayerSaveSchema = require(ReplicatedStorage.Shared.Persistence.PlayerSaveSchema)

local PlayerPersistenceCoordinator = {}

type SaveRequest = {
	Data: any,
	CommitId: string,
	ReleaseSession: boolean,
	ExclusiveReplacement: boolean?,
}

type SessionRecord = {
	Player: Player?,
	SessionId: string,
	Revision: number,
	Pending: SaveRequest?,
	Latest: any?,
	ReleaseRequested: boolean,
	Running: boolean,
	RetryScheduled: boolean,
	ExclusiveOperation: boolean,
	ExclusiveData: any?,
}

local sessionsByUserId: { [number]: SessionRecord } = {}
local started = false
local closing = false
local persistenceDisabledForTestSession = false
local serverIdentity = if game.JobId ~= ""
	then game.JobId
	else "Studio-" .. HttpService:GenerateGUID(false)

local function retry(operation, attempts: number)
	local lastResult = nil
	for attempt = 1, attempts do
		lastResult = operation()
		if lastResult.Succeeded or lastResult.Retryable == false then
			return lastResult
		end
		if attempt < attempts then
			task.wait(PlayerPersistenceConfigs.RetryDelaySeconds * attempt)
		end
	end
	return lastResult
end

local function createSessionId(player: Player): string
	return string.format(
		"%s:%d:%s",
		serverIdentity,
		player.UserId,
		HttpService:GenerateGUID(false)
	)
end

local function kickMessage(reason: string): string
	if reason == "SessionConflict" then
		return "你的存档仍在另一个服务器中使用，请稍后重新加入。"
	end
	if reason == "FutureSaveVersion" or reason == "FutureSaveEnvelopeVersion" then
		return "当前服务器版本无法读取你的存档，请稍后重新加入。"
	end
	return "玩家数据暂时无法安全加载，请稍后重新加入。"
end

local function rejectPlayer(player: Player, reason: string, detail: string?)
	PlayerPersistenceDiagnostics.MarkFailed(player.UserId, reason)
	PlayerDataReadyService.Cancel(player, reason)
	warn(string.format(
		"玩家 %s 持久化会话被拒绝：%s%s",
		player.Name,
		reason,
		if detail then " (" .. detail .. ")" else ""
	))
	if player.Parent == Players then
		player:Kick(kickMessage(reason))
	end
end

local function capture(player: Player)
	local captured, value = pcall(PlayerSaveStateAdapter.Capture, player, os.time())
	if not captured then
		return nil, "SnapshotFailed:" .. tostring(value)
	end
	local normalized, reason = PlayerSaveSchema.Normalize(value)
	if not normalized then
		return nil, "SnapshotInvalid:" .. tostring(reason)
	end
	return normalized, nil
end

local runSaveQueue

local function startSaveQueue(userId: number, record: SessionRecord)
	if record.Running then
		return
	end
	record.Running = true
	task.spawn(runSaveQueue, userId, record)
end

local function scheduleRetry(userId: number, record: SessionRecord)
	if record.RetryScheduled then
		return
	end
	record.RetryScheduled = true
	task.delay(PlayerPersistenceConfigs.FailedSaveRetryDelaySeconds, function()
		record.RetryScheduled = false
		if sessionsByUserId[userId] == record and not record.Running then
			startSaveQueue(userId, record)
		end
	end)
end

local function handleFatalSaveFailure(userId: number, record: SessionRecord, reason: string, detail: string?)
	warn(string.format(
		"玩家 %d 存档会话失效：%s%s",
		userId,
		reason,
		if detail then " (" .. detail .. ")" else ""
	))
	local player = record.Player
	sessionsByUserId[userId] = nil
	if player and player.Parent == Players then
		PlayerDataReadyService.Cancel(player, reason)
		player:Kick("玩家数据已无法安全保存，请重新加入。")
	end
end

runSaveQueue = function(userId: number, record: SessionRecord)
	while sessionsByUserId[userId] == record do
		if not record.Pending then
			if not record.Latest then
				record.Running = false
				return
			end
			record.Pending = {
				Data = record.Latest,
				CommitId = HttpService:GenerateGUID(false),
				ReleaseSession = record.ReleaseRequested,
			}
			record.Latest = nil
		end

		local pending = record.Pending
		PlayerPersistenceDiagnostics.MarkSaving(userId)
		local saved = retry(function()
			return PlayerDataStoreAccess.Commit(
				userId,
				record.SessionId,
				record.Revision,
				pending.CommitId,
				pending.Data,
				pending.ReleaseSession
			)
		end, PlayerPersistenceConfigs.SaveAttempts)
		if not saved.Succeeded then
			PlayerPersistenceDiagnostics.MarkFailed(userId, saved.Reason)
			warn(string.format(
				"玩家 %d 存档保存失败：%s%s",
				userId,
				tostring(saved.Reason),
				if saved.Detail then " (" .. saved.Detail .. ")" else ""
			))
			record.Running = false
			if saved.Retryable then
				scheduleRetry(userId, record)
			else
				handleFatalSaveFailure(userId, record, saved.Reason, saved.Detail)
			end
			return
		end

		record.Revision = saved.Revision
		record.Pending = nil
		if pending.ReleaseSession then
			PlayerPersistenceDiagnostics.MarkReleased(userId, record.Revision)
			sessionsByUserId[userId] = nil
			record.Running = false
			return
		end
		if pending.ExclusiveReplacement then
			record.ExclusiveOperation = false
			record.ExclusiveData = nil
		end
		PlayerPersistenceDiagnostics.MarkSaved(userId, record.Revision)
	end
	record.Running = false
end

local function queueSnapshot(record: SessionRecord, data, releaseSession: boolean)
	if record.ReleaseRequested then
		return false, "SessionReleaseAlreadyQueued"
	end
	record.Latest = data
	if releaseSession then
		record.ReleaseRequested = true
		record.Player = nil
	end
	return true, nil
end

local function queuePlayer(player: Player, releaseSession: boolean): (boolean, string?)
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status ~= "Ready" then
		return false, "PlayerDataNotReady"
	end
	if not readiness.CanSave then
		return false, readiness.Reason or "SaveDisabledForSession"
	end
	local record = sessionsByUserId[player.UserId]
	if not record then
		return false, "SaveSessionUnavailable"
	end
	if record.ExclusiveOperation then
		if releaseSession then
			record.ReleaseRequested = true
			record.Player = nil
			if record.Pending and record.Pending.ExclusiveReplacement then
				record.Pending.ReleaseSession = true
			elseif record.ExclusiveData and not record.Running then
				record.Pending = {
					Data = record.ExclusiveData,
					CommitId = HttpService:GenerateGUID(false),
					ReleaseSession = true,
					ExclusiveReplacement = true,
				}
				startSaveQueue(player.UserId, record)
			end
			return true, nil
		end
		return false, "ExclusiveSaveInProgress"
	end
	local data, reason = capture(player)
	if not data then
		return false, reason
	end
	local queued, queueReason = queueSnapshot(record, data, releaseSession)
	if not queued then
		return false, queueReason
	end
	PlayerPersistenceDiagnostics.MarkDirty(player.UserId)
	startSaveQueue(player.UserId, record)
	return true, nil
end

local function releaseUnappliedSession(
	player: Player,
	sessionId: string,
	revision: number,
	data
)
	local record: SessionRecord = {
		Player = nil,
		SessionId = sessionId,
		Revision = revision,
		Pending = nil,
		Latest = data,
		ReleaseRequested = true,
		Running = false,
		RetryScheduled = false,
		ExclusiveOperation = false,
		ExclusiveData = nil,
	}
	sessionsByUserId[player.UserId] = record
	PlayerPersistenceDiagnostics.MarkDirty(player.UserId)
	startSaveQueue(player.UserId, record)
end

local function loadPlayer(player: Player, sessionId: string)
	PlayerPersistenceDiagnostics.MarkLoading(player.UserId)
	local loaded = retry(function()
		return PlayerDataStoreAccess.Acquire(player.UserId, sessionId)
	end, PlayerPersistenceConfigs.LoadAttempts)
	if not loaded.Succeeded then
		if player.Parent == Players then
			rejectPlayer(player, loaded.Reason, loaded.Detail)
		else
			PlayerDataReadyService.Cancel(player, "PlayerLeftDuringLoad")
		end
		return
	end

	if player.Parent ~= Players or closing then
		PlayerDataReadyService.Cancel(player, if closing then "ServerClosing" else "PlayerLeftDuringLoad")
		releaseUnappliedSession(player, sessionId, loaded.Revision, loaded.Data)
		return
	end

	local applied, applyFailure = pcall(PlayerSaveStateAdapter.Apply, player, loaded.Data, os.time())
	if not applied then
		releaseUnappliedSession(player, sessionId, loaded.Revision, loaded.Data)
		rejectPlayer(player, "StateApplyFailed", tostring(applyFailure))
		return
	end

	local record: SessionRecord = {
		Player = player,
		SessionId = sessionId,
		Revision = loaded.Revision,
		Pending = nil,
		Latest = nil,
		ReleaseRequested = false,
		Running = false,
		RetryScheduled = false,
		ExclusiveOperation = false,
		ExclusiveData = nil,
	}
	sessionsByUserId[player.UserId] = record
	PlayerPersistenceDiagnostics.MarkReady(player.UserId, loaded.Revision)
	PlayerDataReadyService.MarkReady(player, true, nil)
end

local function beginLoad(player: Player)
	PlayerDataReadyService.MarkLoading(player)
	if persistenceDisabledForTestSession then
		local applied, applyFailure = pcall(
			PlayerSaveStateAdapter.Apply,
			player,
			PlayerSaveSchema.Default(),
			os.time()
		)
		if not applied then
			rejectPlayer(player, "StateApplyFailed", tostring(applyFailure))
			return
		end
		PlayerPersistenceDiagnostics.MarkReady(player.UserId, 0)
		PlayerDataReadyService.MarkReady(
			player,
			false,
			"StudioAcceptanceTestSaveDisabled"
		)
		return
	end
	task.spawn(loadPlayer, player, createSessionId(player))
end

function PlayerPersistenceCoordinator.SavePlayer(player: Player): (boolean, string?)
	return queuePlayer(player, false)
end

-- 输入：在线且存档 Ready 的 Player，以及已经完整构建的新业务存档。
-- 输出：Succeeded、Uncertain、Reason、Revision。
-- 内部算法：只在普通保存队列空闲时取得独占权，使用单一 CommitId 同步重试；
-- 网络结果仍不确定时把同一提交留在后台队列继续恢复，禁止旧运行时快照覆盖它。
function PlayerPersistenceCoordinator.CommitReplacement(player: Player, data)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	if player.Parent ~= Players then
		return { Succeeded = false, Uncertain = false, Reason = "PlayerUnavailable", Revision = nil }
	end
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status ~= "Ready" or not readiness.CanSave then
		return { Succeeded = false, Uncertain = false, Reason = "PlayerDataNotReady", Revision = nil }
	end
	local normalized, normalizeReason = PlayerSaveSchema.Normalize(data)
	if not normalized then
		return {
			Succeeded = false,
			Uncertain = false,
			Reason = normalizeReason or "InvalidReplacementData",
			Revision = nil,
		}
	end

	local record = sessionsByUserId[player.UserId]
	if not record then
		return { Succeeded = false, Uncertain = false, Reason = "SaveSessionUnavailable", Revision = nil }
	end
	if record.ReleaseRequested
		or record.ExclusiveOperation
		or record.Running
		or record.Pending ~= nil
		or record.Latest ~= nil
		or record.RetryScheduled then
		return { Succeeded = false, Uncertain = false, Reason = "SaveSessionBusy", Revision = nil }
	end

	record.ExclusiveOperation = true
	record.ExclusiveData = normalized
	record.Running = true
	local commitId = HttpService:GenerateGUID(false)
	PlayerPersistenceDiagnostics.MarkSaving(player.UserId)
	local saved = retry(function()
		return PlayerDataStoreAccess.Commit(
			player.UserId,
			record.SessionId,
			record.Revision,
			commitId,
			normalized,
			false
		)
	end, PlayerPersistenceConfigs.SaveAttempts)

	if not saved.Succeeded then
		PlayerPersistenceDiagnostics.MarkFailed(player.UserId, saved.Reason)
		record.Running = false
		if saved.Retryable and sessionsByUserId[player.UserId] == record then
			record.Pending = {
				Data = normalized,
				CommitId = commitId,
				ReleaseSession = record.ReleaseRequested,
				ExclusiveReplacement = true,
			}
			scheduleRetry(player.UserId, record)
			return {
				Succeeded = false,
				Uncertain = true,
				Reason = saved.Reason or "CommitResultUncertain",
				Revision = nil,
			}
		end

		record.ExclusiveOperation = false
		record.ExclusiveData = nil
		handleFatalSaveFailure(
			player.UserId,
			record,
			saved.Reason or "ReplacementCommitFailed",
			saved.Detail
		)
		return {
			Succeeded = false,
			Uncertain = false,
			Reason = saved.Reason or "ReplacementCommitFailed",
			Revision = nil,
		}
	end

	record.Revision = saved.Revision
	record.Running = false
	PlayerPersistenceDiagnostics.MarkSaved(player.UserId, record.Revision)
	if record.ReleaseRequested and sessionsByUserId[player.UserId] == record then
		record.Pending = {
			Data = normalized,
			CommitId = HttpService:GenerateGUID(false),
			ReleaseSession = true,
			ExclusiveReplacement = true,
		}
		startSaveQueue(player.UserId, record)
	end
	return {
		Succeeded = true,
		Uncertain = false,
		Reason = nil,
		Revision = record.Revision,
	}
end

-- 只由替换提交的协调器在运行时重载完成后调用；keepLocked 用于等待踢出恢复的失败路径。
function PlayerPersistenceCoordinator.FinishReplacement(
	player: Player,
	keepLocked: boolean
): boolean
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(keepLocked) == "boolean", "keepLocked 必须是 boolean")
	local record = sessionsByUserId[player.UserId]
	if not record or not record.ExclusiveOperation then
		return false
	end
	if keepLocked or (record.Pending and record.Pending.ExclusiveReplacement) then
		return false
	end

	local replacementData = record.ExclusiveData
	record.ExclusiveData = nil
	record.ExclusiveOperation = false
	if record.ReleaseRequested and replacementData and not record.Running then
		record.Pending = {
			Data = replacementData,
			CommitId = HttpService:GenerateGUID(false),
			ReleaseSession = true,
			ExclusiveReplacement = true,
		}
		startSaveQueue(player.UserId, record)
	end
	return true
end

local function scheduleResetKick(player: Player, message: string)
	task.delay(0.25, function()
		if player.Parent == Players then
			player:Kick(message)
		end
	end)
end

-- 输入：点击 Studio 一键删档的在线 Player。
-- 输出：Succeeded、Reason、Detail；成功后玩家会退出，下一次 Play 载入默认档。
-- 内部算法：禁止新保存 → 等正在执行的保存结束 → 提交默认档并释放租约 → 删除开发 Key → 退出。
function PlayerPersistenceCoordinator.DeleteStudioSave(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	if not RunService:IsStudio() then
		return { Succeeded = false, Reason = "StudioOnly", Detail = nil }
	end
	if player.Parent ~= Players then
		return { Succeeded = false, Reason = "PlayerUnavailable", Detail = nil }
	end
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status ~= "Ready" then
		return { Succeeded = false, Reason = "PlayerDataNotReady", Detail = nil }
	end
	local record = sessionsByUserId[player.UserId]
	if not record then
		return { Succeeded = false, Reason = "SaveSessionUnavailable", Detail = nil }
	end

	-- 先从会话索引移除并关闭门禁，确保 PlayerRemoving/Autosave 不会把旧内存重新写回。
	sessionsByUserId[player.UserId] = nil
	record.Pending = nil
	record.Latest = nil
	record.ReleaseRequested = true
	PlayerDataReadyService.Cancel(player, "StudioSaveReset")

	local deadline = os.clock() + PlayerPersistenceConfigs.ShutdownWaitSeconds
	while record.Running and os.clock() < deadline do
		task.wait(0.05)
	end
	if record.Running then
		local reason = "SaveQueueBusy"
		warn(string.format("Studio 删档等待保存队列超时：%s/%d", player.Name, player.UserId))
		scheduleResetKick(player, "Studio 测试删档失败，请查看 Output 后重新 Play。")
		return { Succeeded = false, Reason = reason, Detail = nil }
	end

	-- 先用当前 Session/Revision 提交默认档，形成防回写屏障。
	-- 即使后续 RemoveAsync 失败，下一次 Play 也只能读到干净默认档。
	local resetCommitId = HttpService:GenerateGUID(false)
	local resetCommitted = retry(function()
		return PlayerDataStoreAccess.Commit(
			player.UserId,
			record.SessionId,
			record.Revision,
			resetCommitId,
			PlayerSaveSchema.Default(),
			true
		)
	end, PlayerPersistenceConfigs.SaveAttempts)
	if not resetCommitted.Succeeded then
		warn(string.format(
			"Studio 测试删档防回写提交失败：%s/%d (%s%s)",
			player.Name,
			player.UserId,
			resetCommitted.Reason or "Unknown",
			if resetCommitted.Detail then ": " .. resetCommitted.Detail else ""
		))
		scheduleResetKick(player, "Studio 测试删档失败，请查看 Output 后重新 Play。")
		return {
			Succeeded = false,
			Reason = resetCommitted.Reason or "ResetCommitFailed",
			Detail = resetCommitted.Detail,
		}
	end

	local deleted = PlayerDataStoreAccess.DeleteStudioSave(player.UserId)
	if not deleted.Succeeded then
		warn(string.format(
			"Studio 测试删档失败：%s/%d (%s%s)",
			player.Name,
			player.UserId,
			deleted.Reason or "Unknown",
			if deleted.Detail then ": " .. deleted.Detail else ""
		))
		scheduleResetKick(player, "Studio 测试删档失败，请查看 Output 后重新 Play。")
		return deleted
	end

	print(string.format("Studio 测试存档已删除：Player_%d", player.UserId))
	scheduleResetKick(player, "Studio 测试存档已删除，请重新 Play。")
	return deleted
end

local function playerRemoving(player: Player)
	-- Capture 在任何 yield 之前完成，避免 PlayerStateService 删除状态树后再读取。
	local queued, reason = queuePlayer(player, true)
	if not queued and reason and reason:sub(1, 14) == "SnapshotFailed" then
		warn(string.format("玩家 %s 离服快照失败：%s", player.Name, reason))
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
		queuePlayer(player, true)
	end
	for userId, record in sessionsByUserId do
		startSaveQueue(userId, record)
	end
	local deadline = os.clock() + PlayerPersistenceConfigs.ShutdownWaitSeconds
	while next(sessionsByUserId) ~= nil and os.clock() < deadline do
		task.wait(0.1)
	end
end

function PlayerPersistenceCoordinator.Start()
	if started then
		return
	end
	started = true
	persistenceDisabledForTestSession = StudioTestSessionPolicy.ShouldDisablePersistence()
	if persistenceDisabledForTestSession then
		print("CODEX_STUDIO_ACCEPTANCE_PERSISTENCE_DISABLED")
	end

	Players.PlayerAdded:Connect(beginLoad)
	Players.PlayerRemoving:Connect(playerRemoving)
	game:BindToClose(bindToClose)
	for _, player in Players:GetPlayers() do
		beginLoad(player)
	end
	if not persistenceDisabledForTestSession then
		task.spawn(autosaveLoop)
	end
end

return PlayerPersistenceCoordinator
