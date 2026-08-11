local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneyRunFunnelRules = require(
	ReplicatedStorage.Shared.Analytics.MoneyRunFunnelRules
)

local MoneyRunFunnelRulesSpec = {}

function MoneyRunFunnelRulesSpec.Run(): boolean
	local steps = MoneyRunFunnelRules.GetSteps()
	local expectedThresholds = {
		10,
		50,
		100,
		250,
		500,
		1_000,
		2_500,
		5_000,
		10_000,
		25_000,
		50_000,
		100_000,
		250_000,
		500_000,
		1_000_000,
	}
	assert(#steps == #expectedThresholds, "金币漏斗门槛数量错误")
	for index, threshold in expectedThresholds do
		assert(steps[index].Step == index, "金币漏斗步骤编号错误")
		assert(steps[index].Threshold == threshold, "金币漏斗门槛顺序错误")
	end

	local partial = MoneyRunFunnelRules.GetCrossedSteps(250, 2)
	assert(#partial == 2, "从第 2 步到 250 应补齐 2 个步骤")
	assert(partial[1].Step == 3 and partial[2].Step == 4, "补齐步骤不是递增顺序")

	local jump = MoneyRunFunnelRules.GetCrossedSteps(1_000_000, 0)
	assert(#jump == #steps, "一次跨过全部门槛时必须逐级返回")
	assert(jump[#jump].Threshold == 1_000_000, "最后一个门槛必须是 1M")

	local none = MoneyRunFunnelRules.GetCrossedSteps(250, 4)
	assert(#none == 0, "已完成的门槛不应重复返回")
	assert(table.isfrozen(MoneyRunFunnelRules), "金币漏斗规则模块必须只读")
	return true
end

return MoneyRunFunnelRulesSpec
