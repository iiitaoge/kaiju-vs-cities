--[[
	职责：按成长线生成怪兽共用升级价格。
	输入：ProgressionId 和目标等级。
	输出：从 2 级开始的不可变价格表。
	不负责：出生点建造价格、扣款、权限或运行时升级。
]]

local MonsterCatalog = require(script.Parent.MonsterCatalog)
local MonsterLevelProgressionRules = require(script.Parent.MonsterLevelProgressionRules)
local MonsterProgressionConfigs = require(script.Parent.MonsterProgressionConfigs)

local configs = {}

for progressionId, progression in pairs(MonsterProgressionConfigs) do
	local costs = {}
	for targetLevel = 2, assert(MonsterCatalog.GetMaxLevel(progressionId)) do
		costs[targetLevel] = MonsterLevelProgressionRules.ScaleIntegerByStages(
			progression.UpgradeBaseCost,
			progression.UpgradeCostGrowthStages,
			targetLevel - 1
		)
	end
	configs[progressionId] = table.freeze(costs)
end

return table.freeze(configs)
