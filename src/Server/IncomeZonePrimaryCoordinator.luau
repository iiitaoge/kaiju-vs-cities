--[[
	职责：执行产钱区域单一主入口的解锁、建造或升级事务。
	输入：Player、RegionId；具体动作由最新权威状态决定。
	输出：Succeeded、Reason、Action、最新 Snapshot、NextButtonState。
	内部算法：同玩家同区域加锁 → 权威查询 → 扣款/区域事务 → 重查并确认状态提交。
	不负责：实体按钮、Remote、价格计算、模板解析、存档或 UI。
]]

local IncomeZoneActionQuery = require(script.Parent.IncomeZoneActionQuery)
local RegionUpgradeCityCoordinator = require(script.Parent.RegionUpgradeCityCoordinator)
local RegionUpgradeService = require(script.Parent.RegionUpgradeService)

local IncomeZonePrimaryCoordinator = {}

local locks: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" })

local function result(succeeded: boolean, reason: string?, action: string, snapshot)
	return {
		Succeeded = succeeded,
		Reason = reason,
		Action = action,
		Snapshot = snapshot,
		NextButtonState = if snapshot then snapshot.PrimaryButtonState else "Locked",
	}
end

local function executeUnlocked(player: Player, regionId: string)
	local before = IncomeZoneActionQuery.Get(player, regionId)
	if not before then
		return result(false, "UnknownIncomeZone", "None", nil)
	end
	local action = before.PrimaryAction
	local permission = before.Primary
	if not permission.Allowed then
		return result(false, permission.Reason or "ActionLocked", action, before)
	end
	if not permission.Affordable then
		return result(false, "InsufficientMoney", action, before)
	end

	if action == "Unlock" then
		RegionUpgradeService.Unlock(player, regionId)
	elseif action == "Build" or action == "Upgrade" then
		RegionUpgradeCityCoordinator.Upgrade(player, regionId)
	else
		return result(false, "ActionLocked", action, before)
	end

	local after = IncomeZoneActionQuery.Get(player, regionId)
	if not after then
		return result(false, "StateQueryFailed", action, nil)
	end
	local committed = if action == "Unlock"
		then after.Unlocked
		else after.Level == permission.TargetLevel
	return result(
		committed,
		if committed then nil else "RegionActionNotCommitted",
		action,
		after
	)
end

function IncomeZonePrimaryCoordinator.Execute(player: Player, regionId: string)
	local playerLocks = locks[player]
	if not playerLocks then
		playerLocks = {}
		locks[player] = playerLocks
	end
	if playerLocks[regionId] then
		local snapshot = IncomeZoneActionQuery.Get(player, regionId)
		local busy = result(false, "ActionBusy", "None", snapshot)
		busy.NextButtonState = "Processing"
		return busy
	end

	playerLocks[regionId] = true
	local succeeded, outcome = xpcall(function()
		return executeUnlocked(player, regionId)
	end, debug.traceback)
	playerLocks[regionId] = nil
	if not succeeded then
		warn(string.format("产钱区域主操作异常：%s/%s (%s)", player.Name, regionId, tostring(outcome)))
		return result(false, "RegionTransactionError", "None", IncomeZoneActionQuery.Get(player, regionId))
	end
	return outcome
end

return IncomeZonePrimaryCoordinator
