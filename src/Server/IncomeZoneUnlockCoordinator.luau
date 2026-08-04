--[[
	职责：执行产钱区域独立 Unlock 按钮的服务器权威事务。

	输入：Player、RegionId。
	输出：Succeeded、Reason、Action、最新 Snapshot、NextButtonState。
	内部算法：同玩家同区域加锁 → 校验 Unlock 权限/余额 → 扣款并写 Unlocked →
		刷新整条 Zone 解锁链的静态场景；始终保持区域 Level 不变，不创建房屋。

	不负责：区域建造/升级、Boost、按钮 Instance 查找、客户端表现或存档。
]]

local IncomeZoneActionQuery = require(script.Parent.IncomeZoneActionQuery)
local PlayerRegionTransactionLock = require(script.Parent.PlayerRegionTransactionLock)
local PlayerZoneSceneVisibilityService = require(
	script.Parent.PlayerZoneSceneVisibilityService
)
local RegionUpgradeService = require(script.Parent.RegionUpgradeService)

local IncomeZoneUnlockCoordinator = {}

local function result(succeeded: boolean, reason: string?, snapshot)
	return {
		Succeeded = succeeded,
		Reason = reason,
		Action = "Unlock",
		Snapshot = snapshot,
		NextButtonState = if snapshot then snapshot.UnlockButtonState else "Locked",
	}
end

local function executeLocked(player: Player, regionId: string)
	local before = IncomeZoneActionQuery.Get(player, regionId)
	if not before then
		return result(false, "UnknownIncomeZone", nil)
	end
	if not before.Unlock.Allowed then
		return result(false, before.Unlock.Reason or "ActionLocked", before)
	end
	if not before.Unlock.Affordable then
		return result(false, "InsufficientMoney", before)
	end

	local _, unlockState = RegionUpgradeService.Unlock(player, regionId)
	local after = IncomeZoneActionQuery.Get(player, regionId)
	if not after or not after.Unlocked then
		return result(
			false,
			if unlockState == "Insufficient" then "InsufficientMoney" else "RegionUnlockNotCommitted",
			after
		)
	end

	local visibility = PlayerZoneSceneVisibilityService.ApplyAll(player)
	if not visibility.Succeeded then
		warn(string.format(
			"区域已解锁但场景可见性刷新失败：%s/%s (%s)",
			player.Name,
			regionId,
			visibility.Reason or "Unknown"
		))
	end
	return result(true, nil, after)
end

function IncomeZoneUnlockCoordinator.Execute(player: Player, regionId: string)
	local release = PlayerRegionTransactionLock.TryAcquire(player, regionId)
	if not release then
		local snapshot = IncomeZoneActionQuery.Get(player, regionId)
		local busy = result(false, "ActionBusy", snapshot)
		busy.NextButtonState = "Processing"
		return busy
	end

	local succeeded, outcome = xpcall(function()
		return executeLocked(player, regionId)
	end, debug.traceback)
	release()
	if not succeeded then
		warn(string.format(
			"产钱区域解锁异常：%s/%s (%s)",
			player.Name,
			regionId,
			tostring(outcome)
		))
		return result(false, "RegionTransactionError", IncomeZoneActionQuery.Get(player, regionId))
	end
	return outcome
end

return IncomeZoneUnlockCoordinator
