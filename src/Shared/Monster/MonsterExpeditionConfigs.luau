--[[
	职责：定义每种 MonsterKey 的正式出征、怪兽互殴和死亡恢复数值。
	输入：调用方按 MonsterKey 查表。
	输出：移动、奖励、防守检测、战斗和恢复配置。
	不负责：模型、动画资源、玩家状态、目标选择或网络。
]]

local function createDefinition()
	local movement = table.freeze({
		MoveSpeed = 16,
		TurnDuration = 0.75,
	})
	local defense = table.freeze({
		DefenderDetectionRadius = 45,
	})
	local combatMovement = table.freeze({
		DesiredGap = 2,
		MaxGap = 5,
		MoveSpeed = 16,
		TurnDuration = 0.75,
	})
	local combatAnimation = table.freeze({
		SelectionMode = "Sequence",
		HitProgress = 0.65,
		Speed = 1,
	})
	local combat = table.freeze({
		Damage = 25,
		AttackInterval = 1,
		Movement = combatMovement,
		Animation = combatAnimation,
	})
	return table.freeze({
		Movement = movement,
		RewardAmount = 10,
		RecoveryDuration = 10,
		Defense = defense,
		Combat = combat,
	})
end

return table.freeze({
	P1 = createDefinition(),
	P4 = createDefinition(),
})
