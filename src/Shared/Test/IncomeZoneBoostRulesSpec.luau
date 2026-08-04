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
		Transactions = {
			{ Kind = "Income", Cost = 10, Factor = 2 },
			{ Kind = "Health", Cost = 20, Factor = 2 },
			{ Kind = "AutoIncome", Cost = 30, Enabled = true },
		},
	}
end

function IncomeZoneBoostRulesSpec.Run(): boolean
	local allowed = IncomeZoneBoostRules.Evaluate(input())
	assert(allowed.Allowed and allowed.Affordable, "可购买 Boost 被拒绝")
	assert(allowed.TransactionKind == "Income" and allowed.Cost == 10, "第一笔 Boost 不是收入")
	assert(allowed.TargetIncomeMultiplier == 2, "收入倍率目标错误")
	assert(allowed.TargetHealthMultiplier == 1, "收入事务修改了生命倍率")
	assert(not allowed.TargetAutoIncome, "收入事务提前开启自动领取")

	local healthInput = input()
	healthInput.CurrentIncomeMultiplier = 2
	local health = IncomeZoneBoostRules.Evaluate(healthInput)
	assert(health.TransactionKind == "Health" and health.Cost == 20, "第二笔 Boost 不是生命")
	assert(health.TargetHealthMultiplier == 2, "生命倍率目标错误")
	assert(not health.TargetAutoIncome, "生命事务提前开启自动领取")

	local autoInput = input()
	autoInput.CurrentIncomeMultiplier = 2
	autoInput.CurrentHealthMultiplier = 2
	local auto = IncomeZoneBoostRules.Evaluate(autoInput)
	assert(auto.TransactionKind == "AutoIncome" and auto.Cost == 30, "第三笔 Boost 不是自动领取")
	assert(auto.TargetAutoIncome and auto.CompletesBoost, "自动领取没有完成 Boost")

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
	purchasedInput.CurrentIncomeMultiplier = 2
	purchasedInput.CurrentHealthMultiplier = 2
	purchasedInput.CurrentAutoIncome = true
	local purchased = IncomeZoneBoostRules.Evaluate(purchasedInput)
	assert(purchased.Reason == "AlreadyBoosted", "重复 Boost 没有拒绝")
	assert(purchased.ButtonState == "Special", "已购买按钮状态错误")
	return true
end

return IncomeZoneBoostRulesSpec
