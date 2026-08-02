--[[
	职责：执行与输入方式无关的怪兽出生点建造/升级购买事务。

	输入：Player、SpawnPointId；Upgrade 由当前状态确定下一等级。
	输出：Succeeded、Reason、Action、Cost、Balance、Record、NextButtonState。
	内部算法：同一玩家同一出生点加锁 → 权威预检查 → 扣款 → Build/Upgrade → 失败退款 → 重查按钮状态。

	不负责：实体按钮、管理 UI、攻击命令、价格计算或表现动画。
]]

local MoneyService = require(script.Parent.MoneyService)
local MonsterSpawnPointActionQuery = require(script.Parent.MonsterSpawnPointActionQuery)
local PlayerMonsterRuntimeCoordinator = require(script.Parent.PlayerMonsterRuntimeCoordinator)

local MonsterSpawnPointPurchaseCoordinator = {}

local locks: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" })

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
	local stateSucceeded, nextButtonState = pcall(
		MonsterSpawnPointActionQuery.GetPrimaryButtonState,
		player,
		spawnPointId
	)
	return {
		Succeeded = succeeded,
		Reason = reason,
		Action = action,
		Cost = cost,
		Balance = MoneyService.Get(player),
		Record = record,
		NextButtonState = if stateSucceeded then nextButtonState else "Locked",
	}
end

local function executeUnlocked(player: Player, spawnPointId: string, action: "Build" | "Upgrade")
	local snapshot = MonsterSpawnPointActionQuery.Get(player, spawnPointId)
	if not snapshot then
		return resultForSpawnPoint(false, "UnknownSpawnPoint", action, 0, player, spawnPointId, nil)
	end
	local actionStatus = snapshot[action]
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
	if not actionStatus.Affordable then
		return resultForSpawnPoint(
			false,
			"InsufficientMoney",
			action,
			actionStatus.Cost,
			player,
			spawnPointId,
			nil
		)
	end

	local spend = MoneyService.TrySpend(player, actionStatus.Cost)
	if not spend.Succeeded then
		return resultForSpawnPoint(
			false,
			"InsufficientMoney",
			action,
			actionStatus.Cost,
			player,
			spawnPointId,
			nil
		)
	end

	local executed, runtimeResultOrError = pcall(function()
		if action == "Build" then
			return PlayerMonsterRuntimeCoordinator.Build(player, spawnPointId)
		end
		return PlayerMonsterRuntimeCoordinator.Upgrade(
			player,
			spawnPointId,
			assert(actionStatus.TargetLevel)
		)
	end)
	if not executed or not runtimeResultOrError.Succeeded then
		MoneyService.Add(player, actionStatus.Cost)
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
			actionStatus.Cost,
			player,
			spawnPointId,
			if executed then runtimeResultOrError.Record else nil
		)
	end

	return resultForSpawnPoint(
		true,
		nil,
		action,
		actionStatus.Cost,
		player,
		spawnPointId,
		runtimeResultOrError.Record
	)
end

local function executeLocked(player: Player, spawnPointId: string, action: "Build" | "Upgrade")
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
			Balance = MoneyService.Get(player),
			Record = nil,
			NextButtonState = "Processing",
		}
	end

	playerLocks[spawnPointId] = true
	local succeeded, resultOrError = xpcall(function()
		return executeUnlocked(player, spawnPointId, action)
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

function MonsterSpawnPointPurchaseCoordinator.ExecutePrimary(player: Player, spawnPointId: string)
	local snapshot = MonsterSpawnPointActionQuery.Get(player, spawnPointId)
	if not snapshot then
		return resultForSpawnPoint(false, "UnknownSpawnPoint", "Build", 0, player, spawnPointId, nil)
	end
	return executeLocked(player, spawnPointId, snapshot.PrimaryAction)
end

return MonsterSpawnPointPurchaseCoordinator
