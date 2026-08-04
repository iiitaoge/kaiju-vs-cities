--[[
	职责：生成一个产钱区域 Boost 按钮的服务器权威快照。
	输入：Player、RegionId。
	输出：当前区域状态、余额、Boost 权限和按钮状态；未知区域返回 nil。
	内部算法：读取状态和配置，再委托纯 Boost 规则计算。
	不负责：扣款、结算收入、修改倍率、生命值或 UI。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IncomeZoneBoostConfigs = require(script.Parent.IncomeZoneBoostConfigs)
local MoneyService = require(script.Parent.MoneyService)
local RegionStateService = require(script.Parent.RegionStateService)
local IncomeZoneBoostRules = require(
	ReplicatedStorage.Shared.Building.IncomeZoneBoostRules
)

local IncomeZoneBoostQuery = {}

function IncomeZoneBoostQuery.Get(player: Player, regionId: string)
	local config = IncomeZoneBoostConfigs[regionId]
	if not config then
		return nil
	end
	local region = RegionStateService.Get(player, regionId)
	local balance = MoneyService.Get(player)
	local permission = IncomeZoneBoostRules.Evaluate({
		Unlocked = region.Unlocked,
		Level = region.Level,
		Balance = balance,
		BoostPurchased = region.BoostPurchased,
		CurrentIncomeMultiplier = region.IncomeMultiplier,
		CurrentHealthMultiplier = region.HealthMultiplier,
		CurrentAutoIncome = region.AutoIncome,
		Transactions = config.Transactions,
	})
	return {
		RegionId = regionId,
		Unlocked = region.Unlocked,
		Level = region.Level,
		Balance = balance,
		IncomeMultiplier = region.IncomeMultiplier,
		HealthMultiplier = region.HealthMultiplier,
		BoostPurchased = region.BoostPurchased,
		AutoIncome = region.AutoIncome,
		Permission = permission,
		NextTransactionKind = permission.TransactionKind,
		BoostCompleted = permission.Completed,
		BoostButtonState = permission.ButtonState,
	}
end

function IncomeZoneBoostQuery.GetButtonState(player: Player, regionId: string): string
	local snapshot = IncomeZoneBoostQuery.Get(player, regionId)
	return if snapshot then snapshot.BoostButtonState else "Locked"
end

return IncomeZoneBoostQuery
