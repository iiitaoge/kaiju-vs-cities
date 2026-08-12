--[[
	职责：执行与输入方式无关的怪兽出生点建造/升级购买事务。

	输入：Player、SpawnPointId；Upgrade 购买下一等级，UpgradeToMax 使用钻石直达满级。
	输出：Succeeded、Reason、Action、Cost、Balance、Record、NextButtonState。
	内部算法：同一玩家同一出生点加锁 → 权威预检查 → 按动作扣金币/钻石 → Build/Upgrade → 失败退款 → 重查按钮状态。

	不负责：实体按钮、管理 UI、攻击命令、价格计算或表现动画。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiamondService = require(script.Parent.DiamondService)
local GameAnalyticsGateway = require(script.Parent.Analytics.GameAnalyticsGateway)
local PlayerJourneyAnalyticsCoordinator = require(
	script.Parent.Analytics.PlayerJourneyAnalyticsCoordinator
)
local DefenseMonsterActionQuery = require(script.Parent.DefenseMonsterActionQuery)
local MoneyService = require(script.Parent.MoneyService)
local PurchaseStateService = require(script.Parent.PurchaseStateService)
local TaskEventBus = require(script.Parent.TaskEventBus)
local MonsterSpawnPointActionQuery = require(script.Parent.MonsterSpawnPointActionQuery)
local PlayerMonsterRuntimeCoordinator = require(script.Parent.PlayerMonsterRuntimeCoordinator)
local PlayerDefenseMonsterRuntimeCoordinator = require(
	script.Parent.PlayerDefenseMonsterRuntimeCoordinator
)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local TaskProtocol = require(ReplicatedStorage.Shared.Task.TaskProtocol)

local MonsterSpawnPointPurchaseCoordinator = {}

local locks: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" })
local exclusiveLocks: { [Player]: boolean } = setmetatable({}, { __mode = "k" })

local function isMaxUpgradeAction(action: string): boolean
	return action == "UpgradeToMax"
		or action == "PaidUpgradeToMax"
end

local function isPaidUpgradeAction(action: string): boolean
	return action == "PaidUpgradeToMax" or action == "PaidUpgrade"
end

local function getPaidUpgradeStatus(player: Player, spawnPointId: string, targetLevel: number)
	if DefenseMonsterSlotCatalog.Get(spawnPointId) then
		local permission = DefenseMonsterActionQuery.Get(player, spawnPointId)
		if not permission then
			return nil
		end
		if permission.Level >= targetLevel then
			return {
				Allowed = false,
				Reason = "TargetLevelReached",
				Cost = 0,
				Affordable = true,
				TargetLevel = targetLevel,
			}
		end
		local runtime = PlayerDefenseMonsterRuntimeCoordinator.CanUpgrade(
			player,
			spawnPointId,
			targetLevel
		)
		return {
			Allowed = runtime.Allowed,
			Reason = runtime.Reason,
			Cost = 0,
			Affordable = true,
			TargetLevel = targetLevel,
		}
	end
	local permission = MonsterSpawnPointActionQuery.Get(player, spawnPointId)
	if not permission then
		return nil
	end
	if permission.Level >= targetLevel then
		return {
			Allowed = false,
			Reason = "TargetLevelReached",
			Cost = 0,
			Affordable = true,
			TargetLevel = targetLevel,
		}
	end
	local runtime = PlayerMonsterRuntimeCoordinator.CanUpgrade(player, spawnPointId, targetLevel)
	return {
		Allowed = runtime.Allowed,
		Reason = runtime.Reason,
		Cost = 0,
		Affordable = true,
		TargetLevel = targetLevel,
	}
end

local function getSnapshot(player: Player, spawnPointId: string)
	return if DefenseMonsterSlotCatalog.Get(spawnPointId)
		then DefenseMonsterActionQuery.Get(player, spawnPointId)
		else MonsterSpawnPointActionQuery.Get(player, spawnPointId)
end

local function getPrimaryButtonState(player: Player, spawnPointId: string): string
	return if DefenseMonsterSlotCatalog.Get(spawnPointId)
		then DefenseMonsterActionQuery.GetPrimaryButtonState(player, spawnPointId)
		else MonsterSpawnPointActionQuery.GetPrimaryButtonState(player, spawnPointId)
end

local function getBuildButtonState(player: Player, spawnPointId: string): string
	return if DefenseMonsterSlotCatalog.Get(spawnPointId)
		then DefenseMonsterActionQuery.GetBuildButtonState(player, spawnPointId)
		else MonsterSpawnPointActionQuery.GetBuildButtonState(player, spawnPointId)
end

local function getDiamondUpgradeButtonState(player: Player, spawnPointId: string): string
	return if DefenseMonsterSlotCatalog.Get(spawnPointId)
		then DefenseMonsterActionQuery.GetDiamondUpgradeButtonState(player, spawnPointId)
		else MonsterSpawnPointActionQuery.GetDiamondUpgradeButtonState(player, spawnPointId)
end

local function getBalance(player: Player, action: string): number
	return if isMaxUpgradeAction(action) then DiamondService.Get(player) else MoneyService.Get(player)
end

local function resultForSpawnPoint(
	succeeded: boolean,
	reason: string?,
	action: string,
	cost: number,
	player: Player,
	spawnPointId: string,
	record
)
	-- 状态刷新属于返回值增强；不能让它把已经提交成功的购买误报为事务失败。
	local stateQuery = if action == "Build"
		then getBuildButtonState
		elseif isMaxUpgradeAction(action)
		then getDiamondUpgradeButtonState
		else getPrimaryButtonState
	local stateSucceeded, nextButtonState = pcall(
		stateQuery,
		player,
		spawnPointId
	)
	return {
		Succeeded = succeeded,
		Reason = reason,
		Action = action,
		Cost = cost,
		Balance = getBalance(player, action),
		Record = record,
		NextButtonState = if stateSucceeded then nextButtonState else "Locked",
	}
end

local function executeUnlocked(
	player: Player,
	spawnPointId: string,
	action: "Build" | "Upgrade" | "UpgradeToMax" | "PaidUpgradeToMax" | "PaidUpgrade",
	paidTargetLevel: number?
)
	local paidUpgrade = isPaidUpgradeAction(action)
	local snapshot = getSnapshot(player, spawnPointId)
	if not snapshot then
		return resultForSpawnPoint(false, "UnknownSpawnPoint", action, 0, player, spawnPointId, nil)
	end
	local actionStatus = if action == "PaidUpgrade" then getPaidUpgradeStatus(
		player,
		spawnPointId,
		assert(paidTargetLevel)
	) elseif isMaxUpgradeAction(action)
		then snapshot.DiamondUpgrade
		else snapshot[action]
	if not actionStatus then
		return resultForSpawnPoint(false, "ActionUnavailable", action, 0, player, spawnPointId, nil)
	end
	if not actionStatus.Allowed then
		return resultForSpawnPoint(
			false,
			actionStatus.Reason or "ActionLocked",
			action,
			actionStatus.Cost,
			player,
			spawnPointId,
			nil
		)
	end
	if not paidUpgrade and not actionStatus.Affordable then
		return resultForSpawnPoint(
			false,
			if isMaxUpgradeAction(action) then "InsufficientDiamonds" else "InsufficientMoney",
			action,
			actionStatus.Cost,
			player,
			spawnPointId,
			nil
		)
	end

	local actionCost = if paidUpgrade then 0 else actionStatus.Cost
	local spend = if paidUpgrade
		then { Succeeded = true, Reason = nil }
		elseif action == "UpgradeToMax"
		then DiamondService.TrySpend(player, actionStatus.Cost)
		else MoneyService.TrySpend(player, actionStatus.Cost)
	if not spend.Succeeded then
		return resultForSpawnPoint(
			false,
			spend.Reason
				or if isMaxUpgradeAction(action) then "InsufficientDiamonds" else "InsufficientMoney",
			action,
			actionCost,
			player,
			spawnPointId,
			nil
		)
	end

	local executed, runtimeResultOrError = pcall(function()
		if action == "Build" then
			if DefenseMonsterSlotCatalog.Get(spawnPointId) then
				return PlayerDefenseMonsterRuntimeCoordinator.Build(player, spawnPointId)
			end
			return PlayerMonsterRuntimeCoordinator.Build(player, spawnPointId)
		end
		local targetLevel = if paidUpgrade and paidTargetLevel
			then paidTargetLevel
			else assert(actionStatus.TargetLevel)
		if DefenseMonsterSlotCatalog.Get(spawnPointId) then
			return PlayerDefenseMonsterRuntimeCoordinator.Upgrade(
				player,
				spawnPointId,
				targetLevel
			)
		end
		return PlayerMonsterRuntimeCoordinator.Upgrade(
			player,
			spawnPointId,
			targetLevel
		)
	end)
	if not executed or not runtimeResultOrError.Succeeded then
		if action == "UpgradeToMax" then
			DiamondService.Add(player, actionStatus.Cost)
		elseif not paidUpgrade then
			MoneyService.Add(player, actionStatus.Cost)
		end
		local reason = if executed
			then runtimeResultOrError.Reason or "RuntimeActionFailed"
			else "RuntimeActionError"
		if not executed then
			warn(string.format("怪兽出生点购买执行异常：%s/%s (%s)", player.Name, spawnPointId, tostring(runtimeResultOrError)))
		end
		return resultForSpawnPoint(
			false,
			reason,
			action,
			actionCost,
			player,
			spawnPointId,
			if executed then runtimeResultOrError.Record else nil
		)
	end

	local targetLevel = paidTargetLevel or actionStatus.TargetLevel
		or (runtimeResultOrError.Record and runtimeResultOrError.Record.Level)
		or 1
	GameAnalyticsGateway.LogDesign(
		player,
		string.format("Gameplay:Monster:%s:%s", action, spawnPointId),
		targetLevel
	)
	if not isMaxUpgradeAction(action) and not isPaidUpgradeAction(action) then
		GameAnalyticsGateway.LogResource(
			player,
			"Sink",
			actionCost,
			"Monster",
			string.format("%s-%s-L%d", action, spawnPointId, targetLevel)
		)
	end
	local balance = getBalance(player, action)
	PlayerJourneyAnalyticsCoordinator.RecordMonsterPurchase(
		player,
		spawnPointId,
		action,
		targetLevel,
		actionCost,
		balance
	)
	if action == "Upgrade" or isMaxUpgradeAction(action) or isPaidUpgradeAction(action) then
		TaskEventBus.Publish(player, {
			Kind = TaskProtocol.EventKinds.MonsterUpgraded,
			SpawnPointId = spawnPointId,
			TargetLevel = targetLevel,
		})
	end

	return resultForSpawnPoint(
		true,
		nil,
		action,
		actionCost,
		player,
		spawnPointId,
		runtimeResultOrError.Record
	)
end

local function executeLocked(
	player: Player,
	spawnPointId: string,
	action: "Build" | "Upgrade" | "UpgradeToMax" | "PaidUpgradeToMax" | "PaidUpgrade",
	paidTargetLevel: number?
)
	local pending = PurchaseStateService.GetPendingMonsterUpgrade(player)
	if pending
		and pending.SpawnPointId == spawnPointId
		and not isPaidUpgradeAction(action)
	then
		return {
			Succeeded = false,
			Reason = "PurchasePending",
			Action = action,
			Cost = 0,
			Balance = getBalance(player, action),
			Record = nil,
			NextButtonState = "Processing",
		}
	end
	if exclusiveLocks[player] then
		return {
			Succeeded = false,
			Reason = "ActionBusy",
			Action = action,
			Cost = 0,
			Balance = getBalance(player, action),
			Record = nil,
			NextButtonState = "Processing",
		}
	end
	local playerLocks = locks[player]
	if not playerLocks then
		playerLocks = {}
		locks[player] = playerLocks
	end
	if playerLocks[spawnPointId] then
		return {
			Succeeded = false,
			Reason = "ActionBusy",
			Action = action,
			Cost = 0,
			Balance = getBalance(player, action),
			Record = nil,
			NextButtonState = "Processing",
		}
	end

	playerLocks[spawnPointId] = true
	local succeeded, resultOrError = xpcall(function()
		return executeUnlocked(player, spawnPointId, action, paidTargetLevel)
	end, debug.traceback)
	playerLocks[spawnPointId] = nil
	if not succeeded then
		warn("怪兽出生点购买事务失败：" .. tostring(resultOrError))
		return resultForSpawnPoint(
			false,
			"PurchaseTransactionError",
			action,
			0,
			player,
			spawnPointId,
			nil
		)
	end
	return resultOrError
end

function MonsterSpawnPointPurchaseCoordinator.Build(player: Player, spawnPointId: string)
	return executeLocked(player, spawnPointId, "Build")
end

function MonsterSpawnPointPurchaseCoordinator.Upgrade(player: Player, spawnPointId: string)
	return executeLocked(player, spawnPointId, "Upgrade")
end

function MonsterSpawnPointPurchaseCoordinator.UpgradeToMax(player: Player, spawnPointId: string)
	return executeLocked(player, spawnPointId, "UpgradeToMax")
end

-- 输入：收据已确认的 Player 和指定出生点。
-- 输出：不扣钻石、直接把该怪兽升级到满级的事务结果。
-- 内部算法：复用同一出生点锁、权威状态查询、运行时升级和失败回滚；只跳过钻石扣除。
function MonsterSpawnPointPurchaseCoordinator.GrantUpgradeToMax(player: Player, spawnPointId: string)
	return executeLocked(player, spawnPointId, "PaidUpgradeToMax", nil)
end

function MonsterSpawnPointPurchaseCoordinator.GrantUpgradeToLevel(
	player: Player,
	spawnPointId: string,
	targetLevel: number
)
	assert(type(targetLevel) == "number" and targetLevel >= 1 and targetLevel % 1 == 0, "targetLevel 无效")
	return executeLocked(player, spawnPointId, "PaidUpgrade", targetLevel)
end

function MonsterSpawnPointPurchaseCoordinator.ExecutePrimary(player: Player, spawnPointId: string)
	local snapshot = getSnapshot(player, spawnPointId)
	if not snapshot then
		return resultForSpawnPoint(false, "UnknownSpawnPoint", "Build", 0, player, spawnPointId, nil)
	end
	return executeLocked(player, spawnPointId, snapshot.PrimaryAction)
end

function MonsterSpawnPointPurchaseCoordinator.IsBusy(player: Player): boolean
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local playerLocks = locks[player]
	return exclusiveLocks[player] == true
		or (playerLocks ~= nil and next(playerLocks) ~= nil)
end

-- 输入：在线 Player 与 SpawnPointId。
-- 输出：该出生点当前是否仍在执行建造/升级事务。
-- 内部算法：读取购买事务的出生点锁；全局独占锁不代表该出生点正在建造。
function MonsterSpawnPointPurchaseCoordinator.IsSpawnPointBusy(
	player: Player,
	spawnPointId: string
): boolean
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 无效")
	local playerLocks = locks[player]
	return playerLocks ~= nil and playerLocks[spawnPointId] == true
end

function MonsterSpawnPointPurchaseCoordinator.TryAcquireExclusive(
	player: Player
): (() -> ())?
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	if MonsterSpawnPointPurchaseCoordinator.IsBusy(player) then
		return nil
	end
	exclusiveLocks[player] = true
	local released = false
	return function()
		if released then
			return
		end
		released = true
		exclusiveLocks[player] = nil
	end
end

return MonsterSpawnPointPurchaseCoordinator
