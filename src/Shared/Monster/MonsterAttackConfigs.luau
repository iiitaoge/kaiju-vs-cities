--[[
	职责：为 MonsterCatalog 中的每个实际等级生成房屋攻击参数。
	输入：调用方按 MonsterKey 查表；输出：不可变攻击配置。
	不负责：选目标、播放动画或提交伤害。
]]

local MonsterCatalog = require(script.Parent.MonsterCatalog)
local MonsterLevelProgressionRules = require(script.Parent.MonsterLevelProgressionRules)
local MonsterProgressionConfigs = require(script.Parent.MonsterProgressionConfigs)

local detection = table.freeze({
	Radius = 30,
	-- 覆盖正式移动检测的 0.1 秒轮询，并保留 0.05 秒调度余量。
	MovementLookAheadSeconds = 0.15,
})
local geometry = table.freeze({ DesiredGap = 1, MaxGap = 3 })
local animation = table.freeze({
	SelectionMode = "Sequence",
	HitProgress = 0.65,
	Speed = 1.3,
})

local configs = {}
for _, definition in MonsterCatalog.GetAll() do
	local progression = MonsterProgressionConfigs[definition.ProgressionId]
	configs[definition.MonsterKey] = table.freeze({
		StructureDamage = MonsterLevelProgressionRules.ScaleIntegerByStages(
			progression.StructureDamageBase,
			progression.StructureDamageGrowthStages,
			definition.Level
		),
		Detection = detection,
		Geometry = geometry,
		Animation = animation,
	})
end

return table.freeze(configs)
