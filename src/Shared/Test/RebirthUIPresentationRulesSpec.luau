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
			RewardText = "Configured reward text",
		},
		RequiredRunEarnings = 1_000_000,
		RemainingRunEarnings = 250_000,
		ActivationAllowed = true,
	})
	assert(insufficient.Enabled and not insufficient.CanExecute, "收入不足时不得点击")
	assert(insufficient.RequirementText == "1M", "门槛应使用紧凑格式")
	assert(insufficient.InfoTitleText == "", "收入不足时不应显示额外标题")

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
			RewardText = "Configured reward text",
		},
		RequiredRunEarnings = 1_000_000,
		RemainingRunEarnings = 0,
		ActivationAllowed = true,
	})
	assert(ready.CanExecute and ready.ActionText == "Rebirth", "资格满足时应允许点击")
	assert(ready.InfoTitleText == "", "资格满足时不应显示 Ready 文案")
	assert(string.find(ready.IntroductionText, "Configured level text", 1, true), "未使用重生等级配置文案")
	assert(string.find(ready.IntroductionText, "Configured reward text", 1, true), "未使用重生奖励配置文案")
	assert(
		not string.find(ready.IntroductionText, "Progress resets", 1, true),
		"不应显示进度重置文案"
	)

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
		tooFar.InfoTitleText == "",
		"距离按钮过远时不应显示额外标题"
	)
	return true
end

return Spec
