--[[
	职责：集中定义怪兽等级、外观路径和正式分段数值曲线。
	不负责：等级映射、扣款、模型生成或攻击流程。
]]

local function stages(earlyGrowth: number, middleGrowth: number, lateGrowth: number)
	local result = {
		{ UntilLevel = 30, Growth = earlyGrowth },
		{ UntilLevel = 50, Growth = middleGrowth },
		{ UntilLevel = 75, Growth = lateGrowth },
	}
	for _, stage in ipairs(result) do
		table.freeze(stage)
	end
	return table.freeze(result)
end

local configs = {
	Godzilla = {
		DisplayName = "Godzilla",
		MonsterKeyPrefix = "Godzilla-L",
		TemplateRoot = "ReplicatedStorage/Godzilla",
		LevelsPerForm = 15,
		FormCount = 5,

		-- 同等级怪兽互殴约十次命中分胜负；后段放缓，避免 75 级指数失控。
		MaxHealthBase = 300,
		MaxHealthGrowthStages = stages(1.16, 1.10, 1.06),
		CombatDamageBase = 30,
		CombatDamageGrowthStages = stages(1.16, 1.10, 1.06),

		-- 前 30 级跟随 R1～R6 的城市跨度，后段逐步降低成长率。
		StructureDamageBase = 50,
		StructureDamageGrowthStages = stages(1.25, 1.12, 1.06),

		-- 奖励与升级费分别压平：保证新形态可达，同时让八栋攻击保持明显但受控的重生推进。
		RewardBase = 100,
		RewardGrowthStages = stages(1.28, 1.08, 1.12),
		UpgradeBaseCost = 500,
		UpgradeCostGrowthStages = stages(1.27, 1.06, 1.10),
	},
}

for progressionId, config in pairs(configs) do
	assert(type(config.DisplayName) == "string" and config.DisplayName ~= "", progressionId .. " DisplayName 无效")
	assert(type(config.MonsterKeyPrefix) == "string" and config.MonsterKeyPrefix ~= "", progressionId .. " Key 前缀无效")
	assert(type(config.TemplateRoot) == "string" and config.TemplateRoot ~= "", progressionId .. " 模板根路径无效")
	table.freeze(config)
end

return table.freeze(configs)
