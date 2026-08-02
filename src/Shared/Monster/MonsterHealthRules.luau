local MonsterHealthRules = {}

export type DamageResult = {
	Succeeded: boolean,
	Reason: string?,
	PreviousHealth: number,
	DamageApplied: number,
	RemainingHealth: number,
	Defeated: boolean,
}

local function isFiniteNonNegative(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
end

-- 输入：当前生命、最大生命和本次伤害。
-- 输出：实际扣除值、剩余生命和是否死亡。
-- 内部算法：伤害只扣到零；不读取攻击者、动画或怪兽状态。
function MonsterHealthRules.ApplyDamage(
	currentHealth: number,
	maxHealth: number,
	damage: number
): DamageResult
	if not isFiniteNonNegative(maxHealth) or maxHealth <= 0 then
		return {
			Succeeded = false,
			Reason = "InvalidMaxHealth",
			PreviousHealth = 0,
			DamageApplied = 0,
			RemainingHealth = 0,
			Defeated = false,
		}
	end
	if not isFiniteNonNegative(currentHealth) or currentHealth > maxHealth then
		return {
			Succeeded = false,
			Reason = "InvalidCurrentHealth",
			PreviousHealth = 0,
			DamageApplied = 0,
			RemainingHealth = 0,
			Defeated = false,
		}
	end
	if not isFiniteNonNegative(damage) then
		return {
			Succeeded = false,
			Reason = "InvalidDamage",
			PreviousHealth = currentHealth,
			DamageApplied = 0,
			RemainingHealth = currentHealth,
			Defeated = currentHealth <= 0,
		}
	end

	local remainingHealth = math.max(0, currentHealth - damage)
	return {
		Succeeded = true,
		Reason = nil,
		PreviousHealth = currentHealth,
		DamageApplied = currentHealth - remainingHealth,
		RemainingHealth = remainingHealth,
		Defeated = remainingHealth <= 0,
	}
end

return MonsterHealthRules
