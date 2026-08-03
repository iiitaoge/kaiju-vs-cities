local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IncomeZoneBoostRules = require(
	ReplicatedStorage.Shared.Building.IncomeZoneBoostRules
)

local IncomeZoneBoostRulesSpec = {}

local function input()
	return {
		Unlocked = true,
		Level = 1,
		Balance = 10,
		BoostPurchased = false,
		CurrentIncomeMultiplier = 1,
		CurrentHealthMultiplier = 1,
		CurrentAutoIncome = false,
		Cost = 10,
		IncomeFactor = 2,
		HealthFactor = 2,
		EnableAutoIncome = true,
	}
end

function IncomeZoneBoostRulesSpec.Run(): boolean
	local allowed = IncomeZoneBoostRules.Evaluate(input())
	assert(allowed.Allowed and allowed.Affordable, "可购买 Boost 被拒绝")
	assert(allowed.TargetIncomeMultiplier == 2, "收入倍率目标错误")
	assert(allowed.TargetHealthMultiplier == 2, "生命倍率目标错误")
	assert(allowed.TargetAutoIncome, "自动收入目标错误")

	local lockedInput = input()
	lockedInput.Level = 0
	local locked = IncomeZoneBoostRules.Evaluate(lockedInput)
	assert(not locked.Allowed and locked.Reason == "RegionNotBuilt", "未建区域可购买 Boost")

	local poorInput = input()
	poorInput.Balance = 9
	local poor = IncomeZoneBoostRules.Evaluate(poorInput)
	assert(poor.Allowed and not poor.Affordable, "余额不足状态错误")
	assert(poor.ButtonState == "Insufficient", "余额不足按钮状态错误")

	local purchasedInput = input()
	purchasedInput.BoostPurchased = true
	local purchased = IncomeZoneBoostRules.Evaluate(purchasedInput)
	assert(purchased.Reason == "AlreadyBoosted", "重复 Boost 没有拒绝")
	assert(purchased.ButtonState == "Special", "已购买按钮状态错误")
	return true
end

return IncomeZoneBoostRulesSpec
