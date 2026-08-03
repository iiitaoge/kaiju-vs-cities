-- 测试版一次性区域 Boost：收入与建筑生命翻倍，并开启自动收入。
local configs = {
	R1 = { Cost = 10, IncomeFactor = 2, HealthFactor = 2, EnableAutoIncome = true },
	R2 = { Cost = 100, IncomeFactor = 2, HealthFactor = 2, EnableAutoIncome = true },
	R3 = { Cost = 500, IncomeFactor = 2, HealthFactor = 2, EnableAutoIncome = true },
	R4 = { Cost = 10, IncomeFactor = 2, HealthFactor = 2, EnableAutoIncome = true },
	R5 = { Cost = 10, IncomeFactor = 2, HealthFactor = 2, EnableAutoIncome = true },
}

for regionId, config in configs do
	assert(type(config.Cost) == "number" and config.Cost >= 0, regionId .. " Boost Cost 无效")
	assert(type(config.IncomeFactor) == "number" and config.IncomeFactor > 0, regionId .. " IncomeFactor 无效")
	assert(type(config.HealthFactor) == "number" and config.HealthFactor > 0, regionId .. " HealthFactor 无效")
	assert(type(config.EnableAutoIncome) == "boolean", regionId .. " EnableAutoIncome 无效")
	table.freeze(config)
end

return table.freeze(configs)
