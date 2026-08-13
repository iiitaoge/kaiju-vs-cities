local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.UI.RebirthUIPresentationRules)

local Spec = {}

local bonuses = {
	IncomeMultiplier = 1.25,
	BuildSpeedMultiplier = 1.1,
	MonsterDamageMultiplier = 1.15,
	MonsterHealthMultiplier = 1.1,
	MonsterMoveSpeedMultiplier = 1.02,
}

function Spec.Run(): boolean
	local insufficient = Rules.Resolve({
		Status = "Insufficient",
		Count = 0,
		NextCount = 1,
		CurrentMaxLevel = 15,
		NextMaxLevel = 30,
		TotalMaxLevel = 75,
		NextBonuses = bonuses,
		NextPresentation = {
			LevelText = "Configured level text",
			RewardText = "Next rewards: Income x1.25 · Build x1.1",
		},
		RequiredRunEarnings = 1_000_000,
		RemainingRunEarnings = 250_000,
		ActivationAllowed = true,
	})
	assert(insufficient.Enabled and not insufficient.CanExecute, "收入不足时不得点击")
	assert(insufficient.RequirementText == "1M", "门槛应使用紧凑格式")
	assert(insufficient.InfoTitleText == "250K", "剩余门槛显示错误")

	local ready = Rules.Resolve({
		Status = "Ready",
		Count = 0,
		NextCount = 1,
		CurrentMaxLevel = 15,
		NextMaxLevel = 30,
		TotalMaxLevel = 75,
		NextBonuses = bonuses,
		NextPresentation = {
			LevelText = "Configured level text",
			RewardText = "Next rewards: Income x1.25 · Build x1.1",
		},
		RequiredRunEarnings = 1_000_000,
		RemainingRunEarnings = 0,
		ActivationAllowed = true,
	})
	assert(ready.CanExecute and ready.ActionText == "Rebirth", "资格满足时应允许点击")
	assert(string.find(ready.IntroductionText, "Configured level text", 1, true), "未使用重生等级配置文案")
	assert(string.find(ready.IntroductionText, "Income x1.25\nBuild x1.1", 1, true), "重生效果没有逐项换行")
	assert(string.find(ready.IntroductionText, "becomes 1", 1, true), "缺少下一次重生次数")

	local tooFar = Rules.Resolve({
		Status = "Ready",
		Count = 0,
		NextCount = 1,
		CurrentMaxLevel = 15,
		NextMaxLevel = 30,
		TotalMaxLevel = 75,
		NextBonuses = bonuses,
		NextPresentation = {
			LevelText = "Configured level text",
			RewardText = "Configured reward text",
		},
		RequiredRunEarnings = 1_000_000,
		RemainingRunEarnings = 0,
		ActivationAllowed = false,
		ActivationReason = "RebirthButtonTooFar",
	})
	assert(not tooFar.CanExecute, "距离按钮过远时不得点击")
	assert(tooFar.ActionText == "Approach", "距离按钮过远时应提示靠近")
	assert(
		tooFar.InfoTitleText == "Approach the rebirth button",
		"距离按钮过远时说明错误"
	)
	return true
end

return Spec
