--[[
	职责：根据重生次数计算资格门槛和五项永久倍率。
	输入：有限非负整数 RebirthCount、本轮累计收入，以及调用方传入的配置。
	输出：资格判断结果，或包含五个明确字段的倍率快照。
	内部算法：资格门槛按指数增长并封顶；倍率按 Base + Count * PerRebirth 线性增长并可选封顶。
	不负责：读取配置模块、玩家状态、收入来源、运行时应用、存档或重置。
]]

local RebirthProgressionRules = {}

export type EligibilityConfig = {
	BaseRequiredRunEarnings: number,
	RequirementGrowth: number,
	MaximumRequiredRunEarnings: number?,
}

export type BonusConfig = {
	BaseMultiplier: number,
	PerRebirth: number,
	MaximumMultiplier: number?,
}

export type BonusesConfig = {
	IncomeMultiplier: BonusConfig,
	BuildSpeedMultiplier: BonusConfig,
	MonsterDamageMultiplier: BonusConfig,
	MonsterHealthMultiplier: BonusConfig,
	MonsterMoveSpeedMultiplier: BonusConfig,
}

export type EligibilityResult = {
	Allowed: boolean,
	Reason: string?,
	RequiredRunEarnings: number,
	RemainingRunEarnings: number,
	NextRebirthCount: number,
}

export type BonusSnapshot = {
	IncomeMultiplier: number,
	BuildSpeedMultiplier: number,
	MonsterDamageMultiplier: number,
	MonsterHealthMultiplier: number,
	MonsterMoveSpeedMultiplier: number,
}

local function assertFiniteNonNegative(value: number, name: string)
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value >= 0,
		name .. " 必须是有限非负数"
	)
end

local function assertRebirthCount(rebirthCount: number)
	assertFiniteNonNegative(rebirthCount, "rebirthCount")
	assert(rebirthCount % 1 == 0, "rebirthCount 必须是整数")
end

local function requiredRunEarnings(
	rebirthCount: number,
	config: EligibilityConfig
): number
	assert(type(config) == "table", "eligibilityConfig 必须是 table")
	assertFiniteNonNegative(config.BaseRequiredRunEarnings, "BaseRequiredRunEarnings")
	assert(config.BaseRequiredRunEarnings > 0, "BaseRequiredRunEarnings 必须大于 0")
	assertFiniteNonNegative(config.RequirementGrowth, "RequirementGrowth")
	assert(config.RequirementGrowth >= 1, "RequirementGrowth 必须大于等于 1")

	local maximum = config.MaximumRequiredRunEarnings
	if maximum ~= nil then
		assertFiniteNonNegative(maximum, "MaximumRequiredRunEarnings")
		assert(maximum >= config.BaseRequiredRunEarnings, "资格门槛上限不得低于初始门槛")
	end

	local requirement = config.BaseRequiredRunEarnings
		* config.RequirementGrowth ^ rebirthCount
	if maximum ~= nil then
		return math.min(requirement, maximum)
	end
	assert(requirement < math.huge, "资格门槛计算溢出；请配置 MaximumRequiredRunEarnings")
	return requirement
end

local function resolveBonus(rebirthCount: number, config: BonusConfig, name: string): number
	assert(type(config) == "table", name .. " 配置必须是 table")
	assertFiniteNonNegative(config.BaseMultiplier, name .. ".BaseMultiplier")
	assert(config.BaseMultiplier > 0, name .. ".BaseMultiplier 必须大于 0")
	assertFiniteNonNegative(config.PerRebirth, name .. ".PerRebirth")

	local maximum = config.MaximumMultiplier
	if maximum ~= nil then
		assertFiniteNonNegative(maximum, name .. ".MaximumMultiplier")
		assert(maximum >= config.BaseMultiplier, name .. " 上限不得低于基础倍率")
	end

	local multiplier = config.BaseMultiplier + rebirthCount * config.PerRebirth
	if maximum ~= nil then
		return math.min(multiplier, maximum)
	end
	assert(multiplier < math.huge, name .. " 倍率计算溢出")
	return multiplier
end

function RebirthProgressionRules.EvaluateEligibility(
	rebirthCount: number,
	runEarnings: number,
	config: EligibilityConfig
): EligibilityResult
	assertRebirthCount(rebirthCount)
	assertFiniteNonNegative(runEarnings, "runEarnings")

	local requirement = requiredRunEarnings(rebirthCount, config)
	local remaining = math.max(0, requirement - runEarnings)
	local allowed = remaining == 0
	return {
		Allowed = allowed,
		Reason = if allowed then nil else "RunEarningsRequirementNotMet",
		RequiredRunEarnings = requirement,
		RemainingRunEarnings = remaining,
		NextRebirthCount = rebirthCount + 1,
	}
end

function RebirthProgressionRules.ResolveBonuses(
	rebirthCount: number,
	config: BonusesConfig
): BonusSnapshot
	assertRebirthCount(rebirthCount)
	assert(type(config) == "table", "bonusesConfig 必须是 table")

	return {
		IncomeMultiplier = resolveBonus(
			rebirthCount,
			config.IncomeMultiplier,
			"IncomeMultiplier"
		),
		BuildSpeedMultiplier = resolveBonus(
			rebirthCount,
			config.BuildSpeedMultiplier,
			"BuildSpeedMultiplier"
		),
		MonsterDamageMultiplier = resolveBonus(
			rebirthCount,
			config.MonsterDamageMultiplier,
			"MonsterDamageMultiplier"
		),
		MonsterHealthMultiplier = resolveBonus(
			rebirthCount,
			config.MonsterHealthMultiplier,
			"MonsterHealthMultiplier"
		),
		MonsterMoveSpeedMultiplier = resolveBonus(
			rebirthCount,
			config.MonsterMoveSpeedMultiplier,
			"MonsterMoveSpeedMultiplier"
		),
	}
end

return table.freeze(RebirthProgressionRules)
