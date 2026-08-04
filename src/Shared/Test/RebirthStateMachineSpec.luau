local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthStateMachine = require(
	ReplicatedStorage.Shared.Progression.RebirthStateMachine
)

local RebirthStateMachineSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "RebirthStateMachineSpec: " .. message)
end

local function begin()
	local opened = RebirthStateMachine.Apply(RebirthStateMachine.New(), {
		Kind = "Begin",
	})
	expect(opened.Accepted, "Begin 应被接受")
	expect(opened.State.Mode == "CheckingEligibility", "Begin 应进入资格检查")
	expect(opened.State.CycleId == 1, "首次流程 CycleId 应为 1")
	expect(opened.Effect and opened.Effect.Kind == "CheckEligibility", "缺少资格检查 Effect")
	return opened.State
end

function RebirthStateMachineSpec.Run(): boolean
	local checking = begin()
	local eligible = RebirthStateMachine.Apply(checking, {
		Kind = "EligibilityResolved",
		CycleId = checking.CycleId,
		Allowed = true,
	})
	expect(eligible.State.Mode == "AwaitingConfirmation", "资格通过后应等待确认")
	expect(eligible.Effect and eligible.Effect.Kind == "ShowConfirmation", "缺少确认 Effect")

	local confirmed = RebirthStateMachine.Apply(eligible.State, {
		Kind = "Confirm",
		CycleId = eligible.State.CycleId,
	})
	expect(confirmed.State.Mode == "Committing", "确认后应提交重生")
	expect(confirmed.Effect and confirmed.Effect.Kind == "CommitRebirth", "缺少提交 Effect")

	local committed = RebirthStateMachine.Apply(confirmed.State, {
		Kind = "CommitSucceeded",
		CycleId = confirmed.State.CycleId,
	})
	expect(committed.State.Mode == "ReloadingRuntime", "提交后应重载当前服务器运行时")
	expect(committed.Effect and committed.Effect.Kind == "ReloadRuntime", "缺少重载 Effect")

	local completed = RebirthStateMachine.Apply(committed.State, {
		Kind = "RuntimeReloadSucceeded",
		CycleId = committed.State.CycleId,
	})
	expect(completed.State.Mode == "Idle", "重载成功后应回到 Idle")
	expect(completed.Effect and completed.Effect.Kind == "NotifyCompleted", "缺少完成 Effect")

	local reloadFailureChecking = begin()
	local reloadFailureEligible = RebirthStateMachine.Apply(reloadFailureChecking, {
		Kind = "EligibilityResolved",
		CycleId = reloadFailureChecking.CycleId,
		Allowed = true,
	})
	local reloadFailureConfirmed = RebirthStateMachine.Apply(reloadFailureEligible.State, {
		Kind = "Confirm",
		CycleId = reloadFailureEligible.State.CycleId,
	})
	local reloadFailureCommitted = RebirthStateMachine.Apply(reloadFailureConfirmed.State, {
		Kind = "CommitSucceeded",
		CycleId = reloadFailureConfirmed.State.CycleId,
	})
	local reloadFailed = RebirthStateMachine.Apply(reloadFailureCommitted.State, {
		Kind = "RuntimeReloadFailed",
		CycleId = reloadFailureCommitted.State.CycleId,
	})
	expect(reloadFailed.State.Mode == "RecoveryRequired", "重载失败必须进入恢复态")
	expect(reloadFailed.Effect and reloadFailed.Effect.Kind == "RecoverSession", "重载失败缺少恢复 Effect")

	local ineligibleChecking = begin()
	local ineligible = RebirthStateMachine.Apply(ineligibleChecking, {
		Kind = "EligibilityResolved",
		CycleId = ineligibleChecking.CycleId,
		Allowed = false,
		Reason = "GrowthRequirementNotMet",
	})
	expect(ineligible.State.Mode == "Idle", "资格不足后应回到 Idle")
	expect(ineligible.State.LastReason == "GrowthRequirementNotMet", "资格失败原因丢失")
	expect(ineligible.Effect and ineligible.Effect.Kind == "NotifyRejected", "缺少拒绝 Effect")

	local cancelledChecking = begin()
	local cancelled = RebirthStateMachine.Apply(cancelledChecking, { Kind = "Cancel" })
	expect(cancelled.State.Mode == "Idle", "检查期间取消应回到 Idle")
	local stale = RebirthStateMachine.Apply(cancelled.State, {
		Kind = "EligibilityResolved",
		CycleId = cancelledChecking.CycleId,
		Allowed = true,
	})
	expect(not stale.Accepted and stale.Reason == "InvalidTransition", "取消后的结果不应重新打开确认")

	local retryOpened = RebirthStateMachine.Apply(cancelled.State, { Kind = "Begin" })
	expect(retryOpened.State.CycleId == 2, "新流程必须递增 CycleId")
	local oldCycle = RebirthStateMachine.Apply(retryOpened.State, {
		Kind = "EligibilityResolved",
		CycleId = 1,
		Allowed = true,
	})
	expect(not oldCycle.Accepted and oldCycle.Reason == "StaleCycle", "过期 Cycle 应被拒绝")

	local retryEligible = RebirthStateMachine.Apply(retryOpened.State, {
		Kind = "EligibilityResolved",
		CycleId = retryOpened.State.CycleId,
		Allowed = true,
	})
	local retryConfirmed = RebirthStateMachine.Apply(retryEligible.State, {
		Kind = "Confirm",
		CycleId = retryEligible.State.CycleId,
	})
	local busyCancel = RebirthStateMachine.Apply(retryConfirmed.State, { Kind = "Cancel" })
	expect(not busyCancel.Accepted and busyCancel.Reason == "RequestBusy", "提交期间禁止取消")

	local failed = RebirthStateMachine.Apply(retryConfirmed.State, {
		Kind = "CommitFailed",
		CycleId = retryConfirmed.State.CycleId,
		Reason = "DataStoreUnavailable",
	})
	expect(failed.State.Mode == "Idle", "确定未提交时应允许重新尝试")
	expect(failed.Effect and failed.Effect.Kind == "NotifyFailed", "缺少提交失败 Effect")

	local uncertainChecking = begin()
	local uncertainEligible = RebirthStateMachine.Apply(uncertainChecking, {
		Kind = "EligibilityResolved",
		CycleId = uncertainChecking.CycleId,
		Allowed = true,
	})
	local uncertainConfirmed = RebirthStateMachine.Apply(uncertainEligible.State, {
		Kind = "Confirm",
		CycleId = uncertainEligible.State.CycleId,
	})
	local uncertain = RebirthStateMachine.Apply(uncertainConfirmed.State, {
		Kind = "CommitUncertain",
		CycleId = uncertainConfirmed.State.CycleId,
	})
	expect(uncertain.State.Mode == "RecoveryRequired", "提交不确定必须进入恢复态")
	expect(uncertain.Effect and uncertain.Effect.Kind == "RecoverSession", "缺少恢复 Effect")
	local blocked = RebirthStateMachine.Apply(uncertain.State, { Kind = "Begin" })
	expect(not blocked.Accepted and blocked.Reason == "RecoveryRequired", "恢复态禁止再次重生")

	local closed = RebirthStateMachine.Apply(uncertain.State, { Kind = "SessionClosed" })
	expect(closed.State.Mode == "Idle" and closed.State.CycleId == 0, "会话关闭应清空状态")
	return true
end

return RebirthStateMachineSpec
