local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TaskConfigs = require(ReplicatedStorage.Shared.Task.TaskConfigs)
local TaskPresentationProtocol = require(
	ReplicatedStorage.Shared.Task.TaskPresentationProtocol
)
local TaskPresentationRules = require(
	ReplicatedStorage.Shared.Task.TaskPresentationRules
)
local TaskRules = require(ReplicatedStorage.Shared.Task.TaskRules)

local TaskPresentationRulesSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "TaskPresentationRulesSpec: " .. message)
end

function TaskPresentationRulesSpec.Run(): boolean
	local valid, reason = TaskRules.ValidateConfig(TaskConfigs)
	expect(valid and reason == nil, "首批任务配置必须有效")

	local states = {}
	for taskId, definition in TaskConfigs.Tasks do
		states[taskId] = TaskRules.GetInitialState(definition)
	end

	local snapshot = TaskPresentationRules.Build(TaskConfigs, states, {
		R2 = { Unlocked = true, Level = 3 },
		R3 = { Unlocked = false, Level = 0 },
	})
	expect(snapshot.Visible, "存在未完成任务时卡片必须显示")
	expect(snapshot.TaskId == "UnlockR3", "必须按 Order 显示首个任务")
	expect(
		snapshot.Text == "Upgrade Region 2 to Level 5, then unlock Region 3",
		"区域解锁任务文案错误"
	)
	expect(snapshot.Current == 3 and snapshot.Target == 5, "区域等级进度错误")
	expect(
		snapshot.RewardKind == "Diamond" and snapshot.RewardAmount == 100,
		"R3 钻石奖励展示错误"
	)

	states.UnlockR3.Progress.UnlockZone.Completed = true
	states.UnlockR3.Progress.UnlockZone.Current = 1
	states.UnlockR3.Completed = true
	local nextSnapshot = TaskPresentationRules.Build(TaskConfigs, states, {
		R2 = { Unlocked = true, Level = 5 },
		R3 = { Unlocked = true, Level = 0 },
	})
	expect(nextSnapshot.TaskId == "UnlockR4", "完成 R3 后必须切换到 R4 任务")
	expect(nextSnapshot.Current == 0 and nextSnapshot.Target == 5, "R4 初始进度错误")

	local hiddenStates = {}
	for taskId, definition in TaskConfigs.Tasks do
		local state = TaskRules.GetInitialState(definition)
		state.Completed = true
		hiddenStates[taskId] = state
	end
	local hidden = TaskPresentationRules.Build(TaskConfigs, hiddenStates, {})
	expect(not hidden.Visible, "全部任务完成后卡片必须隐藏")

	local validSnapshot, snapshotReason = TaskPresentationProtocol.Validate(snapshot)
	expect(validSnapshot and snapshotReason == nil, "合法任务快照必须通过协议校验")
	return true
end

return TaskPresentationRulesSpec
