--[[
	职责：计算产钱区域一次性 Boost 的权限、目标倍率和按钮状态。
	输入：区域状态、余额和调用方传入的纯配置数值。
	输出：Allowed、Reason、目标倍率、自动收入状态和 ButtonState。
	内部算法：只验证输入并计算结果；不读取玩家、Instance、配置模块或运行时状态。
]]

local IncomeZoneBoostRules = {}

local function isFiniteNonNegative(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
end

local function isFinitePositive(value): boolean
	return isFiniteNonNegative(value) and value > 0
end

function IncomeZoneBoostRules.Evaluate(input)
	if type(input) ~= "table"
		or type(input.Unlocked) ~= "boolean"
		or not isFiniteNonNegative(input.Level)
		or input.Level % 1 ~= 0
		or not isFiniteNonNegative(input.Balance)
		or type(input.BoostPurchased) ~= "boolean"
		or not isFiniteNonNegative(input.CurrentIncomeMultiplier)
		or not isFinitePositive(input.CurrentHealthMultiplier)
		or type(input.CurrentAutoIncome) ~= "boolean"
		or not isFiniteNonNegative(input.Cost)
		or not isFinitePositive(input.IncomeFactor)
		or not isFinitePositive(input.HealthFactor)
		or type(input.EnableAutoIncome) ~= "boolean"
	then
		return {
			Allowed = false,
			Affordable = false,
			Reason = "InvalidInput",
			Cost = 0,
			TargetIncomeMultiplier = 1,
			TargetHealthMultiplier = 1,
			TargetAutoIncome = false,
			ButtonState = "Locked",
		}
	end

	local targetIncomeMultiplier = input.CurrentIncomeMultiplier * input.IncomeFactor
	local targetHealthMultiplier = input.CurrentHealthMultiplier * input.HealthFactor
	if input.BoostPurchased then
		return {
			Allowed = false,
			Affordable = true,
			Reason = "AlreadyBoosted",
			Cost = input.Cost,
			TargetIncomeMultiplier = input.CurrentIncomeMultiplier,
			TargetHealthMultiplier = input.CurrentHealthMultiplier,
			TargetAutoIncome = input.CurrentAutoIncome,
			ButtonState = "Special",
		}
	end
	if not input.Unlocked or input.Level < 1 then
		return {
			Allowed = false,
			Affordable = false,
			Reason = "RegionNotBuilt",
			Cost = input.Cost,
			TargetIncomeMultiplier = targetIncomeMultiplier,
			TargetHealthMultiplier = targetHealthMultiplier,
			TargetAutoIncome = input.EnableAutoIncome,
			ButtonState = "Locked",
		}
	end

	local affordable = input.Balance >= input.Cost
	return {
		Allowed = true,
		Affordable = affordable,
		Reason = if affordable then nil else "InsufficientMoney",
		Cost = input.Cost,
		TargetIncomeMultiplier = targetIncomeMultiplier,
		TargetHealthMultiplier = targetHealthMultiplier,
		TargetAutoIncome = input.EnableAutoIncome,
		ButtonState = if affordable then "Ready" else "Insufficient",
	}
end

return table.freeze(IncomeZoneBoostRules)
