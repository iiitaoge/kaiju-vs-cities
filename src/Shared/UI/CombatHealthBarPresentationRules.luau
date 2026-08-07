--[[
	职责：把怪兽或房屋的只读战斗状态映射为血条显示快照。
	输入：怪兽状态或房屋攻击数，以及当前/最大生命。
	输出：Enabled、FillRatio 和动态压缩数值文本。
	内部算法：只允许明确的场外怪兽状态或活动房屋攻击会话显示，并把比例限制在 0～1。
	不负责：读取 Instance、复制状态、克隆模板或播放动画。
]]

local CompactNumberFormatter = require(script.Parent.CompactNumberFormatter)

local CombatHealthBarPresentationRules = {}

local visibleMonsterStates = table.freeze({
	Releasing = true,
	MovingToTarget = true,
	Encountering = true,
	AttackingStructure = true,
	Defending = true,
	FightingMonster = true,
	Returning = true,
})

local function finiteNonNegative(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
end

local function disabled()
	return {
		Enabled = false,
		FillRatio = 0,
		Text = "",
	}
end

local function resolveHealth(currentHealth, maxHealth, enabled: boolean)
	if not enabled
		or not finiteNonNegative(currentHealth)
		or not finiteNonNegative(maxHealth)
		or maxHealth <= 0
	then
		return disabled()
	end

	local clampedHealth = math.clamp(currentHealth, 0, maxHealth)
	return {
		Enabled = true,
		FillRatio = clampedHealth / maxHealth,
		Text = string.format(
			"%s/%s",
			CompactNumberFormatter.Format(clampedHealth),
			CompactNumberFormatter.Format(maxHealth)
		),
	}
end

function CombatHealthBarPresentationRules.ResolveMonster(input)
	if type(input) ~= "table" then
		return disabled()
	end
	return resolveHealth(
		input.CurrentHealth,
		input.MaxHealth,
		visibleMonsterStates[input.State] == true
	)
end

function CombatHealthBarPresentationRules.ResolveHouse(input)
	if type(input) ~= "table" then
		return disabled()
	end
	local activeAttackCount = input.ActiveAttackCount
	return resolveHealth(
		input.CurrentHealth,
		input.MaxHealth,
		input.LifeState == "Alive"
			and type(activeAttackCount) == "number"
			and activeAttackCount % 1 == 0
			and activeAttackCount > 0
	)
end

return table.freeze(CombatHealthBarPresentationRules)
