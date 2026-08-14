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
		R1 = { Unlocked = true, Level = 3 },
		R2 = { Unlocked = false, Level = 0 },
	})
	expect(snapshot.Visible, "存在未完成任务时卡片必须显示")
	expect(snapshot.TaskId == "UpgradeR1To5", "必须先显示 R1 升级任务")
	expect(
		snapshot.Text == "Upgrade Region 1 to Level 5",
		"区域升级任务文案错误"
	)
	expect(snapshot.Current == 3 and snapshot.Target == 5, "区域等级进度错误")
	expect(
		snapshot.RewardKind == "Diamond" and snapshot.RewardAmount == 5,
		"R1 升级钻石奖励展示错误"
	)

	states.UpgradeR1To5.Progress.ReachRegionLevel.Completed = true
	states.UpgradeR1To5.Progress.ReachRegionLevel.Current = 5
	states.UpgradeR1To5.Completed = true
	local nextSnapshot = TaskPresentationRules.Build(TaskConfigs, states, {
		R1 = { Unlocked = true, Level = 5 },
		R2 = { Unlocked = false, Level = 0 },
	})
	expect(nextSnapshot.TaskId == "UnlockR2", "升级 R1 后必须切换到 R2 解锁任务")
	expect(nextSnapshot.Current == 0 and nextSnapshot.Target == 1, "R2 解锁进度错误")

	states.UnlockR2.Progress.UnlockZone.Completed = true
	states.UnlockR2.Progress.UnlockZone.Current = 1
	states.UnlockR2.Completed = true
	local r2Upgrade = TaskPresentationRules.Build(TaskConfigs, states, {
		R1 = { Unlocked = true, Level = 5 },
		R2 = { Unlocked = true, Level = 3 },
	})
	expect(r2Upgrade.TaskId == "UpgradeR2To5", "解锁 R2 后必须切换到 R2 升级任务")
	expect(r2Upgrade.Current == 3 and r2Upgrade.Target == 5, "R2 升级进度错误")

	states.UpgradeR2To5.Progress.ReachRegionLevel.Completed = true
	states.UpgradeR2To5.Progress.ReachRegionLevel.Current = 5
	states.UpgradeR2To5.Completed = true
	local r3Unlock = TaskPresentationRules.Build(TaskConfigs, states, {
		R2 = { Unlocked = true, Level = 5 },
		R3 = { Unlocked = false, Level = 0 },
	})
	expect(r3Unlock.TaskId == "UnlockR3", "R2 达到 Level 5 后必须切换到 R3 解锁任务")
	expect(r3Unlock.Current == 0 and r3Unlock.Target == 1, "R3 解锁进度错误")
	expect(r3Unlock.RewardAmount == 10, "R3 解锁奖励拆分错误")

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
