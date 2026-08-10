--[[
	职责：定义四个依次开放的怪兽出生点建造价格，以及共用的 75 级升级价格。
	价格只作为服务器购买事务和未来 UI 的输入，不执行扣款。
]]

local MonsterSpawnPointCatalog = require(script.Parent.MonsterSpawnPointCatalog)
local MonsterUpgradeEconomyConfigs = require(script.Parent.MonsterUpgradeEconomyConfigs)

local buildCosts = table.freeze({
	["M1-S1"] = 250,
	["M1-S2"] = 500_000,
	["M1-S3"] = 12_000_000,
	["M1-S4"] = 150_000_000,
})
local configs = {}
for _, definition in MonsterSpawnPointCatalog.GetAll() do
	configs[definition.SpawnPointId] = {
		BuildCost = assert(
			buildCosts[definition.SpawnPointId],
			definition.SpawnPointId .. " 缺少建造价格"
		),
		UpgradeCostByTargetLevel = assert(
			MonsterUpgradeEconomyConfigs[definition.ProgressionId],
			definition.ProgressionId .. " 缺少升级价格"
		),
	}
end

for spawnPointId, config in pairs(configs) do
	assert(
		type(config.BuildCost) == "number"
			and config.BuildCost >= 0
			and config.BuildCost < math.huge,
		spawnPointId .. " BuildCost 无效"
	)
	for targetLevel, cost in pairs(config.UpgradeCostByTargetLevel) do
		assert(type(targetLevel) == "number" and targetLevel >= 2 and targetLevel % 1 == 0, "升级等级无效")
		assert(type(cost) == "number" and cost >= 0 and cost < math.huge, "升级价格无效")
	end
	table.freeze(config)
end

return table.freeze(configs)
