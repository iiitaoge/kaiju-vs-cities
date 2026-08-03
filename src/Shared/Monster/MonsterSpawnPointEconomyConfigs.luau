--[[
	职责：定义怪兽出生点的测试版建造与升级价格。
	价格只作为服务器购买事务和未来 UI 的输入，不执行扣款。
]]

local MonsterLevelProgressionRules = require(script.Parent.MonsterLevelProgressionRules)
local MonsterProgressionConfigs = require(script.Parent.MonsterProgressionConfigs)
local MonsterSpawnPointCatalog = require(script.Parent.MonsterSpawnPointCatalog)

local progression = MonsterProgressionConfigs.Godzilla
local upgradeCosts = {}
for targetLevel = 2, assert(MonsterSpawnPointCatalog.GetMaxLevel("M1-S1")) do
	upgradeCosts[targetLevel] = MonsterLevelProgressionRules.ScaleInteger(
		progression.UpgradeBaseCost,
		progression.UpgradeCostGrowth,
		targetLevel - 1
	)
end

local configs = {
	["M1-S1"] = {
		BuildCost = progression.BuildCost,
		UpgradeCostByTargetLevel = upgradeCosts,
	},
}

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
	table.freeze(config.UpgradeCostByTargetLevel)
	table.freeze(config)
end

return table.freeze(configs)
