local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TaskCompletionFunnelRules = require(
	ReplicatedStorage.Shared.Analytics.TaskCompletionFunnelRules
)
local TaskConfigs = require(ReplicatedStorage.Shared.Task.TaskConfigs)

local TaskCompletionFunnelRulesSpec = {}

function TaskCompletionFunnelRulesSpec.Run(): boolean
	local orderedTasks = {}
	for _, task in TaskConfigs.Tasks do
		table.insert(orderedTasks, task)
	end
	table.sort(orderedTasks, function(left, right)
		return left.Order < right.Order
	end)

	local steps = TaskCompletionFunnelRules.GetSteps()
	assert(#steps == #orderedTasks + 1, "任务汇总漏斗必须包含入口和全部任务")
	assert(steps[1].TaskId == nil, "任务漏斗第一步必须是任务列表入口")
	assert(
		steps[1].Name == "TASK LIST AVAILABLE",
		"任务漏斗入口名称错误"
	)
	for index, task in orderedTasks do
		local step = steps[index + 1]
		assert(step.Step == index + 1, "任务漏斗步骤编号错误")
		assert(step.TaskId == task.Id, "任务漏斗任务顺序错误")
		assert(
			TaskCompletionFunnelRules.GetTaskStep(task.Id) == step,
			"任务漏斗任务索引错误"
		)
	end
	assert(
		TaskCompletionFunnelRules.GetTaskStep("Unknown") == nil,
		"未知任务不得进入漏斗"
	)
	assert(table.isfrozen(TaskCompletionFunnelRules), "任务漏斗规则必须只读")
	return true
end

return TaskCompletionFunnelRulesSpec
