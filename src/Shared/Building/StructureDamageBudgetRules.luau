--[[
	职责：把一次出征剩余的建筑伤害预算分配给当前房屋。
	输入：非负剩余预算、正数当前生命。
	输出：本栋计划伤害、计划后的剩余预算，以及本击是否足以摧毁。
	不负责：选择房屋、提交伤害、奖励、动画或处理并发后的实际扣血差异。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local StructureDamageBudgetRules = {}

export type Allocation = {
	DamageToApply: number,
	RemainingDamage: number,
	WillDestroy: boolean,
}

function StructureDamageBudgetRules.Allocate(
	remainingDamage: number,
	currentHealth: number
): Allocation
	assert(
		ValueValidation.IsFiniteNumber(remainingDamage) and remainingDamage >= 0,
		"remainingDamage 必须是有限非负数"
	)
	assert(
		ValueValidation.IsFiniteNumber(currentHealth) and currentHealth > 0,
		"currentHealth 必须是有限正数"
	)

	local damageToApply = math.min(remainingDamage, currentHealth)
	return {
		DamageToApply = damageToApply,
		RemainingDamage = remainingDamage - damageToApply,
		WillDestroy = damageToApply >= currentHealth,
	}
end

return table.freeze(StructureDamageBudgetRules)
