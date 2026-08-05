--[[
	职责：在决斗计时到点时只按双方等级确定胜者。
	输入：进攻、防守怪兽等级。
	输出：Attacker 或 Defender；平级固定由防守方获胜。
	不负责：生命、伤害、动画、计时或状态写入。
]]

local MonsterDuelOutcomeRules = {}

local function validLevel(level): boolean
	return type(level) == "number"
		and level == level
		and level < math.huge
		and level >= 1
		and level % 1 == 0
end

function MonsterDuelOutcomeRules.Resolve(attackerLevel: number, defenderLevel: number): "Attacker" | "Defender"
	assert(validLevel(attackerLevel), "attackerLevel 必须是正整数")
	assert(validLevel(defenderLevel), "defenderLevel 必须是正整数")
	return if attackerLevel > defenderLevel then "Attacker" else "Defender"
end

return table.freeze(MonsterDuelOutcomeRules)
