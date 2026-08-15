--[[
	职责：把所有任务按 TaskConfigs.Order 固定映射为一条汇总漏斗。
	输入：GetTaskStep 接收任务 Id；GetSteps 返回完整阶段列表。
	输出：任务列表入口阶段和每个任务的稳定阶段编号、名称。
	内部算法：先按配置 Order 排序，再在入口阶段之后依次加入全部任务。
	不负责：读取任务状态、发送分析事件、计算任务进度或发放奖励。
]]

local TaskConfigs = require(script.Parent.Parent.Task.TaskConfigs)

local TaskCompletionFunnelRules = {}

export type Step = {
	Step: number,
	TaskId: string?,
	Name: string,
}

local orderedTasks = {}
for _, task in TaskConfigs.Tasks do
	table.insert(orderedTasks, task)
end
table.sort(orderedTasks, function(left, right)
	return left.Order < right.Order
end)

local steps = {
	table.freeze({
		Step = 1,
		TaskId = nil,
		Name = "TASK LIST AVAILABLE",
	}),
}
local stepsByTaskId = {}
for index, task in orderedTasks do
	local stepNumber = index + 1
	local step: Step = table.freeze({
		Step = stepNumber,
		TaskId = task.Id,
		Name = "TASK " .. task.Id .. " COMPLETED",
	})
	steps[stepNumber] = step
	stepsByTaskId[task.Id] = step
end

local STEPS: { Step } = table.freeze(steps)
local STEPS_BY_TASK_ID: { [string]: Step } = table.freeze(stepsByTaskId)

function TaskCompletionFunnelRules.GetSteps(): { Step }
	return STEPS
end

function TaskCompletionFunnelRules.GetEntryStep(): Step
	return STEPS[1]
end

function TaskCompletionFunnelRules.GetTaskStep(taskId: string): Step?
	return STEPS_BY_TASK_ID[taskId]
end

return table.freeze(TaskCompletionFunnelRules)
