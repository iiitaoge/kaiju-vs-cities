--[[
	职责：计算建筑单次伤害、等级迁移后的比例血量和满血状态。
	输入：有限的当前生命、最大生命、伤害或新最大生命。
	输出：无副作用的稳定结果。
	不负责：玩家、房屋身份、Instance、奖励、生命周期或存档。
]]

local StructureHealthRules = {}

export type DamageResult = {
	Accepted: boolean,
	Reason: string?,
	PreviousHealth: number,
	RemainingHealth: number,
	MaxHealth: number,
	DamageApplied: number,
	Depleted: boolean,
}

local function isFinite(value): boolean
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function validHealth(currentHealth, maxHealth): boolean
	return isFinite(maxHealth)
		and maxHealth > 0
		and isFinite(currentHealth)
		and currentHealth >= 0
		and currentHealth <= maxHealth
end

function StructureHealthRules.ApplyDamage(
	currentHealth: number,
	maxHealth: number,
	damage: number
): DamageResult
	if not validHealth(currentHealth, maxHealth) then
		return {
			Accepted = false,
			Reason = "InvalidHealth",
			PreviousHealth = currentHealth,
			RemainingHealth = currentHealth,
			MaxHealth = maxHealth,
			DamageApplied = 0,
			Depleted = currentHealth == 0,
		}
	end
	if not isFinite(damage) or damage <= 0 then
		return {
			Accepted = false,
			Reason = "InvalidDamage",
			PreviousHealth = currentHealth,
			RemainingHealth = currentHealth,
			MaxHealth = maxHealth,
			DamageApplied = 0,
			Depleted = currentHealth == 0,
		}
	end
	if currentHealth == 0 then
		return {
			Accepted = false,
			Reason = "HealthDepleted",
			PreviousHealth = 0,
			RemainingHealth = 0,
			MaxHealth = maxHealth,
			DamageApplied = 0,
			Depleted = true,
		}
	end

	local damageApplied = math.min(currentHealth, damage)
	local remainingHealth = currentHealth - damageApplied
	return {
		Accepted = true,
		Reason = nil,
		PreviousHealth = currentHealth,
		RemainingHealth = remainingHealth,
		MaxHealth = maxHealth,
		DamageApplied = damageApplied,
		Depleted = remainingHealth == 0,
	}
end

function StructureHealthRules.MigrateByRatio(
	currentHealth: number,
	previousMaxHealth: number,
	newMaxHealth: number
): number?
	if not validHealth(currentHealth, previousMaxHealth)
		or not isFinite(newMaxHealth)
		or newMaxHealth <= 0 then
		return nil
	end
	return newMaxHealth * (currentHealth / previousMaxHealth)
end

function StructureHealthRules.Full(maxHealth: number): number?
	return if isFinite(maxHealth) and maxHealth > 0 then maxHealth else nil
end

return table.freeze(StructureHealthRules)
