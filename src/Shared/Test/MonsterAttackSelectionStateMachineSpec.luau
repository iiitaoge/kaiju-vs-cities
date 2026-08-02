local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterAttackSelectionStateMachine = require(
	ReplicatedStorage.Shared.Monster.MonsterAttackSelectionStateMachine
)

local MonsterAttackSelectionStateMachineSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "MonsterAttackSelectionStateMachineSpec: " .. message)
end

local function apply(state, event)
	local transition = MonsterAttackSelectionStateMachine.Apply(state, event)
	expect(transition.Accepted, transition.Reason or "状态转换被拒绝")
	return transition
end

-- 输入：无。
-- 输出：目标稳定排序/切换、刷新保持目标、提交恢复、目标离线和关闭全部通过时返回 true。
-- 内部算法：只向纯状态机发送事件，不创建 Player、Remote、相机或 GUI。
function MonsterAttackSelectionStateMachineSpec.Run(): boolean
	local opened = apply(MonsterAttackSelectionStateMachine.New(), {
		Kind = "Open",
		SpawnPointId = "M1-S1",
	})
	expect(opened.State.Mode == "LoadingTargets", "Open 后必须查询目标")
	expect(opened.Effect and opened.Effect.Kind == "QueryTargets", "缺少 QueryTargets Effect")

	local loaded = apply(opened.State, {
		Kind = "TargetsLoaded",
		TargetPlayerIds = { 3, 2, 3, 0 },
	})
	expect(loaded.State.Mode == "Browsing", "目标加载后必须进入 Browsing")
	expect(#loaded.State.TargetPlayerIds == 2, "目标必须去重并过滤无效 ID")
	expect(loaded.Effect and loaded.Effect.TargetPlayerId == 2, "目标必须按 UserId 稳定排序")

	local nextTarget = apply(loaded.State, { Kind = "NextTarget" })
	expect(nextTarget.Effect and nextTarget.Effect.TargetPlayerId == 3, "NextTarget 切换错误")
	local previousTarget = apply(nextTarget.State, { Kind = "PreviousTarget" })
	expect(previousTarget.Effect and previousTarget.Effect.TargetPlayerId == 2, "PreviousTarget 切换错误")

	local refreshing = apply(previousTarget.State, { Kind = "Refresh" })
	local refreshed = apply(refreshing.State, {
		Kind = "TargetsLoaded",
		TargetPlayerIds = { 1, 2, 4 },
	})
	expect(refreshed.Effect and refreshed.Effect.TargetPlayerId == 2, "刷新后必须保持原目标")

	local submitting = apply(refreshed.State, {
		Kind = "SubmitRequested",
		EntryPoint = Vector3.new(10, 0, 20),
	})
	expect(submitting.State.Mode == "Submitting", "提交后必须进入 Submitting")
	expect(
		submitting.Effect
			and submitting.Effect.Kind == "RequestAttack"
			and submitting.Effect.TargetPlayerId == 2,
		"RequestAttack Effect 错误"
	)
	local rejected = apply(submitting.State, {
		Kind = "SubmitRejected",
		Reason = "MonsterBusy",
	})
	expect(rejected.State.Mode == "Browsing", "服务器拒绝后必须允许重试")
	expect(rejected.State.LastReason == "MonsterBusy", "服务器拒绝原因没有保存")

	local resubmitting = apply(rejected.State, {
		Kind = "SubmitRequested",
		EntryPoint = Vector3.new(10, 0, 20),
	})
	local commandResult = { Succeeded = true, CommandId = 7 }
	local accepted = apply(resubmitting.State, {
		Kind = "SubmitAccepted",
		Result = commandResult,
	})
	expect(accepted.State.Mode == "Closed", "接受命令后必须关闭选择")
	expect(
		accepted.Effect
			and accepted.Effect.Kind == "NotifyAccepted"
			and accepted.Effect.TargetPlayerId == 2
			and accepted.Effect.Result == commandResult,
		"NotifyAccepted Effect 错误"
	)

	local unavailableOpen = apply(MonsterAttackSelectionStateMachine.New(), {
		Kind = "Open",
		SpawnPointId = "M1-S1",
	})
	local unavailable = apply(unavailableOpen.State, {
		Kind = "TargetsLoaded",
		TargetPlayerIds = {},
	})
	expect(unavailable.State.Mode == "Unavailable", "空目标必须进入 Unavailable")
	expect(unavailable.Effect and unavailable.Effect.TargetPlayerId == nil, "空目标通知错误")
	expect(apply(unavailable.State, { Kind = "Refresh" }).State.Mode == "LoadingTargets", "Unavailable 必须允许刷新")

	local targetLost = apply(refreshed.State, {
		Kind = "TargetUnavailable",
		TargetPlayerId = 2,
	})
	expect(targetLost.Effect and targetLost.Effect.TargetPlayerId == 4, "目标离线后应选择稳定后继")
	local cancelled = apply(targetLost.State, { Kind = "Cancel" })
	expect(cancelled.State.Mode == "Closed", "Cancel 后必须关闭")
	expect(cancelled.Effect and cancelled.Effect.Kind == "CloseSelection", "缺少 CloseSelection Effect")

	return true
end

return MonsterAttackSelectionStateMachineSpec
