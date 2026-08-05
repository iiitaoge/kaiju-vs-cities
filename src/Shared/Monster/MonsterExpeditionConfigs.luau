--[[
	职责：为每个实际等级生成正式出征、互殴和死亡恢复数值。
	输入：调用方按 MonsterKey 查表；输出：移动、奖励、防守、战斗和恢复配置。
	不负责：模型、动画资源、玩家状态、目标选择或网络。
]]

local MonsterCatalog = require(script.Parent.MonsterCatalog)
local MonsterLevelProgressionRules = require(script.Parent.MonsterLevelProgressionRules)
local MonsterProgressionConfigs = require(script.Parent.MonsterProgressionConfigs)

local walkAnimation = table.freeze({
	ReferenceMoveSpeed = 40,
	MinPlaybackSpeed = 1,
	MaxPlaybackSpeed = 3,
})
local movement = table.freeze({
	MoveSpeed = 100,
	MaxTravelDuration = 3,
	TimingSafetyMargin = 0.1,
	TurnDuration = 0.2,
	WalkAnimation = walkAnimation,
})
local combatMovement = table.freeze({
	DesiredGap = 2,
	MaxGap = 5,
	MoveSpeed = 100,
	MaxTravelDuration = 3,
	TimingSafetyMargin = 0.1,
	TurnDuration = 0.2,
	WalkAnimation = walkAnimation,
})
local combatAnimation = table.freeze({
	SelectionMode = "Sequence",
	HitProgress = 0.65,
	Speed = 2,
})

local configs = {}
for _, definition in MonsterCatalog.GetAll() do
	local progression = MonsterProgressionConfigs[definition.ProgressionId]
	local combat = table.freeze({
		Damage = MonsterLevelProgressionRules.ScaleIntegerByStages(
			progression.CombatDamageBase,
			progression.CombatDamageGrowthStages,
			definition.Level
		),
		AttackInterval = 0.5,
		Movement = combatMovement,
		Animation = combatAnimation,
	})
	configs[definition.MonsterKey] = table.freeze({
		Movement = movement,
		RewardAmount = MonsterLevelProgressionRules.ScaleIntegerByStages(
			progression.RewardBase,
			progression.RewardGrowthStages,
			definition.Level
		),
		RecoveryDuration = 10,
		Combat = combat,
	})
end

return table.freeze(configs)
