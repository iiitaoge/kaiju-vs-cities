--[[
	职责：集中定义怪兽等级、外观路径和测试期数值曲线。
	不负责：等级映射、扣款、模型生成或攻击流程。
]]

local configs = {
	Godzilla = {
		DisplayName = "Godzilla",
		MonsterKeyPrefix = "Godzilla-L",
		TemplateRoot = "ReplicatedStorage/Godzilla",
		LevelsPerAppearance = 5,
		VisualLevelCount = 3,
		FormCount = 5,

		MaxHealthBase = 100,
		MaxHealthGrowth = 1.04,
		StructureDamageBase = 35,
		StructureDamageGrowth = 1.03,
		CombatDamageBase = 25,
		CombatDamageGrowth = 1.03,
		RewardBase = 10,
		RewardGrowth = 1.02,

		BuildCost = 250,
		UpgradeBaseCost = 25,
		UpgradeCostGrowth = 1.04,
	},
}

for progressionId, config in pairs(configs) do
	assert(type(config.DisplayName) == "string" and config.DisplayName ~= "", progressionId .. " DisplayName 无效")
	assert(type(config.MonsterKeyPrefix) == "string" and config.MonsterKeyPrefix ~= "", progressionId .. " Key 前缀无效")
	assert(type(config.TemplateRoot) == "string" and config.TemplateRoot ~= "", progressionId .. " 模板根路径无效")
	table.freeze(config)
end

return table.freeze(configs)
