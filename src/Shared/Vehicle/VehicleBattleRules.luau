--[[
	职责：计算一个载具战斗回合的生命变化和胜负。
	输入：双方当前生命值与攻击力。
	输出：双方回合后的生命值，以及 Continue、Attacker、Defender 结果。
	内部算法：双方同时造成一次攻击；双方同时归零时防守方获胜。
	不负责：攻击间隔、战斗状态、模型、玩家或奖励。
]]

local VehicleBattleRules = {}

export type RoundResult = {
	DefenderHealth: number,
	AttackerHealth: number,
	Outcome: "Continue" | "Attacker" | "Defender",
}

local function validNonNegative(value: number): boolean
	return type(value) == "number" and value == value and value < math.huge and value >= 0
end

local function validPositive(value: number): boolean
	return validNonNegative(value) and value > 0
end

function VehicleBattleRules.ResolveRound(
	defenderHealth: number,
	defenderAttack: number,
	attackerHealth: number,
	attackerAttack: number
): RoundResult
	assert(validNonNegative(defenderHealth), "defenderHealth 必须是有限非负数")
	assert(validPositive(defenderAttack), "defenderAttack 必须是有限正数")
	assert(validNonNegative(attackerHealth), "attackerHealth 必须是有限非负数")
	assert(validPositive(attackerAttack), "attackerAttack 必须是有限正数")

	local nextDefenderHealth = math.max(0, defenderHealth - attackerAttack)
	local nextAttackerHealth = math.max(0, attackerHealth - defenderAttack)
	local outcome: "Continue" | "Attacker" | "Defender" = "Continue"
	if nextDefenderHealth <= 0 then
		outcome = if nextAttackerHealth <= 0 then "Defender" else "Attacker"
	elseif nextAttackerHealth <= 0 then
		outcome = "Defender"
	end

	return {
		DefenderHealth = nextDefenderHealth,
		AttackerHealth = nextAttackerHealth,
		Outcome = outcome,
	}
end

return table.freeze(VehicleBattleRules)
