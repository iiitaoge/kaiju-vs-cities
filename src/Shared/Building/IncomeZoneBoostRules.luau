--[[
	职责：计算同一 Boost 按钮下一笔顺序事务的权限、成本和目标状态。
	输入：区域状态、余额，以及 Income → Health → AutoIncome 三笔配置事务。
	输出：下一事务 Kind、目标倍率/自动状态、是否最终完成和 ButtonState。
	不负责：读取玩家、扣款、写状态、迁移生命或领取收入。
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
		or type(input.Transactions) ~= "table"
		or #input.Transactions ~= 3
	then
		return {
			Allowed = false,
			Affordable = false,
			Reason = "InvalidInput",
			Cost = 0,
			TransactionKind = nil,
			Completed = false,
			CompletesBoost = false,
			TargetIncomeMultiplier = 1,
			TargetHealthMultiplier = 1,
			TargetAutoIncome = false,
			ButtonState = "Locked",
		}
	end

	local expectedKinds = { "Income", "Health", "AutoIncome" }
	for index, transaction in ipairs(input.Transactions) do
		if type(transaction) ~= "table"
			or transaction.Kind ~= expectedKinds[index]
			or not isFiniteNonNegative(transaction.Cost)
			or (transaction.Kind ~= "AutoIncome" and not isFinitePositive(transaction.Factor))
			or (transaction.Kind == "AutoIncome" and type(transaction.Enabled) ~= "boolean")
		then
			return {
				Allowed = false,
				Affordable = false,
				Reason = "InvalidInput",
				Cost = 0,
				TransactionKind = nil,
				Completed = false,
				CompletesBoost = false,
				TargetIncomeMultiplier = input.CurrentIncomeMultiplier,
				TargetHealthMultiplier = input.CurrentHealthMultiplier,
				TargetAutoIncome = input.CurrentAutoIncome,
				ButtonState = "Locked",
			}
		end
	end

	local nextIndex = nil
	if input.CurrentIncomeMultiplier < input.Transactions[1].Factor then
		nextIndex = 1
	elseif input.CurrentHealthMultiplier < input.Transactions[2].Factor then
		nextIndex = 2
	elseif input.CurrentAutoIncome ~= input.Transactions[3].Enabled then
		nextIndex = 3
	end

	if not nextIndex then
		return {
			Allowed = false,
			Affordable = true,
			Reason = "AlreadyBoosted",
			Cost = 0,
			TransactionKind = nil,
			Completed = true,
			CompletesBoost = true,
			TargetIncomeMultiplier = input.CurrentIncomeMultiplier,
			TargetHealthMultiplier = input.CurrentHealthMultiplier,
			TargetAutoIncome = input.CurrentAutoIncome,
			ButtonState = "Special",
		}
	end

	local transaction = input.Transactions[nextIndex]
	local targetIncomeMultiplier = input.CurrentIncomeMultiplier
	local targetHealthMultiplier = input.CurrentHealthMultiplier
	local targetAutoIncome = input.CurrentAutoIncome
	if transaction.Kind == "Income" then
		targetIncomeMultiplier *= transaction.Factor
	elseif transaction.Kind == "Health" then
		targetHealthMultiplier *= transaction.Factor
	else
		targetAutoIncome = transaction.Enabled
	end
	if not input.Unlocked or input.Level < 1 then
		return {
			Allowed = false,
			Affordable = false,
			Reason = "RegionNotBuilt",
			Cost = transaction.Cost,
			TransactionKind = transaction.Kind,
			Completed = false,
			CompletesBoost = nextIndex == #input.Transactions,
			TargetIncomeMultiplier = targetIncomeMultiplier,
			TargetHealthMultiplier = targetHealthMultiplier,
			TargetAutoIncome = targetAutoIncome,
			ButtonState = "Locked",
		}
	end

	local affordable = input.Balance >= transaction.Cost
	return {
		Allowed = true,
		Affordable = affordable,
		Reason = if affordable then nil else "InsufficientMoney",
		Cost = transaction.Cost,
		TransactionKind = transaction.Kind,
		Completed = false,
		CompletesBoost = nextIndex == #input.Transactions,
		TargetIncomeMultiplier = targetIncomeMultiplier,
		TargetHealthMultiplier = targetHealthMultiplier,
		TargetAutoIncome = targetAutoIncome,
		ButtonState = if affordable then "Ready" else "Insufficient",
	}
end

return table.freeze(IncomeZoneBoostRules)
