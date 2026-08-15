local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialFunnelRules = require(
	ReplicatedStorage.Shared.Analytics.TutorialFunnelRules
)

local TutorialFunnelRulesSpec = {}

function TutorialFunnelRulesSpec.Run(): boolean
	local expectedStepIds = {
		"BuildR1",
		"CollectForR1Upgrade",
		"UpgradeR1",
		"CollectForMonsterBuild",
		"BuildMonster",
		"WaitForMonsterBuild",
		"StartAttack",
		"ChooseTarget",
		"CollectForDefenseMonsterBuild",
		"BuildDefenseMonster",
		"Complete",
	}
	local steps = TutorialFunnelRules.GetSteps()
	assert(#steps == #expectedStepIds, "新手引导漏斗必须包含完整 11 步")
	for index, stepId in expectedStepIds do
		assert(steps[index].Step == index, "新手引导漏斗步骤编号错误")
		assert(steps[index].StepId == stepId, "新手引导漏斗顺序错误")
		assert(
			TutorialFunnelRules.GetStep(stepId) == steps[index],
			"新手引导漏斗索引错误"
		)
	end
	assert(TutorialFunnelRules.GetStep("Unknown") == nil, "未知引导步骤不得进入漏斗")
	assert(table.isfrozen(TutorialFunnelRules), "新手引导漏斗规则必须只读")
	return true
end

return TutorialFunnelRulesSpec
