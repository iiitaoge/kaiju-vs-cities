-- 同一个区域 Boost 按钮依次购买：2x 收入、2x 生命、自动领取。
local function transactions(incomeCost: number, healthCost: number, autoIncomeCost: number)
	local result = {
		table.freeze({ Kind = "Income", Cost = incomeCost, Factor = 2 }),
		table.freeze({ Kind = "Health", Cost = healthCost, Factor = 2 }),
		table.freeze({ Kind = "AutoIncome", Cost = autoIncomeCost, Enabled = true }),
	}
	return table.freeze(result)
end

local configs = {
	R1 = { Transactions = transactions(1_200, 2_000, 3_000) },
	R2 = { Transactions = transactions(8_000, 12_000, 18_000) },
	R3 = { Transactions = transactions(100_000, 150_000, 250_000) },
	R4 = { Transactions = transactions(900_000, 1_200_000, 1_500_000) },
	R5 = { Transactions = transactions(6_000_000, 8_000_000, 10_000_000) },
	R6 = { Transactions = transactions(35_000_000, 45_000_000, 60_000_000) },
}

for regionId, config in configs do
	assert(type(config.Transactions) == "table" and #config.Transactions == 3, regionId .. " Boost 事务无效")
	table.freeze(config)
end

return table.freeze(configs)
