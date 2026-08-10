--[[
	职责：定义六个区域防守怪兽的首次建造价格，并复用 Godzilla 成长线升级价格。
	输入：无。
	输出：DefenseSpawnPointId 对应的只读 BuildCost 和 UpgradeCostByTargetLevel。
	内部算法：建造价格按区域经济阶段递增；升级价格直接引用共用怪兽升级配置。
	不负责：区域解锁、余额、扣款、模型生成或按钮表现。
]]

local DefenseMonsterSlotCatalog = require(script.Parent.DefenseMonsterSlotCatalog)
local MonsterUpgradeEconomyConfigs = require(script.Parent.MonsterUpgradeEconomyConfigs)

local buildCosts = table.freeze({
	["DM-R1"] = 1_500,
	["DM-R2"] = 8_000,
	["DM-R3"] = 80_000,
	["DM-R4"] = 800_000,
	["DM-R5"] = 6_400_000,
	["DM-R6"] = 40_000_000,
})

local configs = {}
for _, definition in DefenseMonsterSlotCatalog.GetAll() do
	local config = {
		BuildCost = assert(
			buildCosts[definition.SpawnPointId],
			definition.SpawnPointId .. " 缺少防守怪兽建造价格"
		),
		UpgradeCostByTargetLevel = assert(
			MonsterUpgradeEconomyConfigs[definition.ProgressionId],
			definition.ProgressionId .. " 缺少怪兽升级价格"
		),
	}
	assert(
		type(config.BuildCost) == "number"
			and config.BuildCost >= 0
			and config.BuildCost < math.huge,
		definition.SpawnPointId .. " BuildCost 无效"
	)
	configs[definition.SpawnPointId] = table.freeze(config)
end

return table.freeze(configs)
