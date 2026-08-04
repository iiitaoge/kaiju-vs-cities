local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Progression = ReplicatedStorage.Shared.Progression
local RebirthProgressionConfigs = require(Progression.RebirthProgressionConfigs)
local RebirthProgressionRules = require(Progression.RebirthProgressionRules)

local RebirthProgressionRulesSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "RebirthProgressionRulesSpec: " .. message)
end

local function expectNear(actual: number, expected: number, message: string)
	expect(math.abs(actual - expected) < 1e-9, message)
end

function RebirthProgressionRulesSpec.Run(): boolean
	local initial = RebirthProgressionRules.ResolveBonuses(
		0,
		RebirthProgressionConfigs.Bonuses
	)
	expectNear(initial.IncomeMultiplier, 1, "零次重生收入倍率应为 1")
	expectNear(initial.BuildSpeedMultiplier, 1, "零次重生建造速度倍率应为 1")
	expectNear(initial.MonsterDamageMultiplier, 1, "零次重生怪兽伤害倍率应为 1")
	expectNear(initial.MonsterHealthMultiplier, 1, "零次重生怪兽生命倍率应为 1")
	expectNear(initial.MonsterMoveSpeedMultiplier, 1, "零次重生怪兽移速倍率应为 1")

	local fourth = RebirthProgressionRules.ResolveBonuses(
		4,
		RebirthProgressionConfigs.Bonuses
	)
	expectNear(fourth.IncomeMultiplier, 2, "收入倍率线性计算错误")
	expectNear(fourth.BuildSpeedMultiplier, 1.4, "建造速度倍率线性计算错误")
	expectNear(fourth.MonsterDamageMultiplier, 1.6, "怪兽伤害倍率线性计算错误")
	expectNear(fourth.MonsterHealthMultiplier, 1.4, "怪兽生命倍率线性计算错误")
	expectNear(fourth.MonsterMoveSpeedMultiplier, 1.08, "怪兽移速倍率线性计算错误")

	local capped = RebirthProgressionRules.ResolveBonuses(
		100,
		RebirthProgressionConfigs.Bonuses
	)
	expectNear(capped.IncomeMultiplier, 10, "收入倍率应封顶")
	expectNear(capped.BuildSpeedMultiplier, 3, "建造速度倍率应封顶")
	expectNear(capped.MonsterDamageMultiplier, 10, "怪兽伤害倍率应封顶")
	expectNear(capped.MonsterHealthMultiplier, 5, "怪兽生命倍率应封顶")
	expectNear(capped.MonsterMoveSpeedMultiplier, 1.5, "怪兽移速倍率应封顶")

	local unavailable = RebirthProgressionRules.EvaluateEligibility(
		2,
		20_000_000,
		RebirthProgressionConfigs.Eligibility
	)
	expect(not unavailable.Allowed, "收入不足时不应允许重生")
	expect(unavailable.RequiredRunEarnings == 25_000_000, "资格门槛增长错误")
	expect(unavailable.RemainingRunEarnings == 5_000_000, "剩余收入计算错误")
	expect(unavailable.NextRebirthCount == 3, "下一次重生次数错误")

	local available = RebirthProgressionRules.EvaluateEligibility(
		2,
		25_000_000,
		RebirthProgressionConfigs.Eligibility
	)
	expect(available.Allowed and available.Reason == nil, "达到门槛后应允许重生")
	expect(available.RemainingRunEarnings == 0, "达到门槛后剩余收入应为 0")

	local custom = RebirthProgressionRules.ResolveBonuses(3, {
		IncomeMultiplier = { BaseMultiplier = 2, PerRebirth = 1 },
		BuildSpeedMultiplier = { BaseMultiplier = 1, PerRebirth = 0 },
		MonsterDamageMultiplier = { BaseMultiplier = 1, PerRebirth = 0 },
		MonsterHealthMultiplier = { BaseMultiplier = 1, PerRebirth = 0 },
		MonsterMoveSpeedMultiplier = { BaseMultiplier = 1, PerRebirth = 0 },
	})
	expectNear(custom.IncomeMultiplier, 5, "规则必须使用调用方传入的配置")
	return true
end

return RebirthProgressionRulesSpec
