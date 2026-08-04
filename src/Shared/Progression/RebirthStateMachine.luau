--[[
	职责：描述无 UI、网络、存档和具体成长公式依赖的重生流程状态。
	输入：当前 State 和一个 Event；异步完成事件必须携带对应 CycleId。
	输出：Accepted、Reason、新 State，以及最多一个待协调 Effect。
	内部算法：资格检查 → 等待确认 → 提交重生 → 当前服务器重载；用 CycleId 拒绝过期响应。
	不负责：决定重生门槛、计算永久收益、写存档、重建运行时、确认 UI 或踢出玩家。
]]

local RebirthStateMachine = {}

export type Mode =
	"Idle"
	| "CheckingEligibility"
	| "AwaitingConfirmation"
	| "Committing"
	| "ReloadingRuntime"
	| "RecoveryRequired"

export type State = {
	Mode: Mode,
	CycleId: number,
	LastReason: string?,
}

export type Effect = {
	Kind:
		"CheckEligibility"
		| "ShowConfirmation"
		| "CommitRebirth"
		| "ReloadRuntime"
		| "NotifyRejected"
		| "NotifyCancelled"
		| "NotifyCompleted"
		| "NotifyFailed"
		| "RecoverSession",
	CycleId: number,
	Reason: string?,
}

-- CommitRebirth 的执行方必须在同一持久化提交中写入永久收益和全新初始进度；
-- ReloadRuntime 只能在该提交明确成功后执行。

export type TransitionResult = {
	Accepted: boolean,
	Reason: string?,
	State: State,
	Effect: Effect?,
}

local validModes = {
	Idle = true,
	CheckingEligibility = true,
	AwaitingConfirmation = true,
	Committing = true,
	ReloadingRuntime = true,
	RecoveryRequired = true,
}

local function state(mode: Mode, cycleId: number, lastReason: string?): State
	return {
		Mode = mode,
		CycleId = cycleId,
		LastReason = lastReason,
	}
end

local function result(
	accepted: boolean,
	reason: string?,
	nextState: State,
	effect: Effect?
): TransitionResult
	return {
		Accepted = accepted,
		Reason = reason,
		State = nextState,
		Effect = effect,
	}
end

local function isState(value): boolean
	return type(value) == "table"
		and validModes[value.Mode] == true
		and type(value.CycleId) == "number"
		and value.CycleId >= 0
		and value.CycleId % 1 == 0
		and (value.LastReason == nil or type(value.LastReason) == "string")
end

local function rejected(current: State, reason: string): TransitionResult
	return result(false, reason, state(current.Mode, current.CycleId, reason), nil)
end

local function eventReason(event, fallback: string): string
	return if type(event.Reason) == "string" and event.Reason ~= ""
		then event.Reason
		else fallback
end

local function hasCurrentCycle(current: State, event): boolean
	return type(event.CycleId) == "number"
		and event.CycleId % 1 == 0
		and event.CycleId == current.CycleId
end

function RebirthStateMachine.New(): State
	return state("Idle", 0, nil)
end

-- 支持的 Event.Kind：Begin、EligibilityResolved、Cancel、Confirm、
-- CommitSucceeded、CommitFailed、CommitUncertain、RuntimeReloadSucceeded、
-- RuntimeReloadFailed、SessionClosed。
function RebirthStateMachine.Apply(current: State, event): TransitionResult
	if not isState(current) then
		return rejected(RebirthStateMachine.New(), "InvalidState")
	end
	if type(event) ~= "table" or type(event.Kind) ~= "string" then
		return rejected(current, "InvalidEvent")
	end

	if event.Kind == "SessionClosed" then
		return result(true, nil, RebirthStateMachine.New(), nil)
	end

	if event.Kind == "Begin" then
		if current.Mode == "RecoveryRequired" then
			return rejected(current, "RecoveryRequired")
		end
		if current.Mode ~= "Idle" then
			return rejected(current, "RequestBusy")
		end
		local cycleId = current.CycleId + 1
		return result(true, nil, state("CheckingEligibility", cycleId, nil), {
			Kind = "CheckEligibility",
			CycleId = cycleId,
			Reason = nil,
		})
	end

	if event.Kind == "Cancel" then
		if current.Mode == "Idle" then
			return result(true, nil, current, nil)
		end
		if current.Mode == "CheckingEligibility"
			or current.Mode == "AwaitingConfirmation" then
			return result(true, nil, state("Idle", current.CycleId, "Cancelled"), {
				Kind = "NotifyCancelled",
				CycleId = current.CycleId,
				Reason = "Cancelled",
			})
		end
		return rejected(
			current,
			if current.Mode == "RecoveryRequired" then "RecoveryRequired" else "RequestBusy"
		)
	end

	if not hasCurrentCycle(current, event) then
		return rejected(current, "StaleCycle")
	end

	if event.Kind == "EligibilityResolved" then
		if current.Mode ~= "CheckingEligibility" then
			return rejected(current, "InvalidTransition")
		end
		if type(event.Allowed) ~= "boolean" then
			return rejected(current, "InvalidEligibilityResult")
		end
		if event.Allowed then
			return result(
				true,
				nil,
				state("AwaitingConfirmation", current.CycleId, nil),
				{
					Kind = "ShowConfirmation",
					CycleId = current.CycleId,
					Reason = nil,
				}
			)
		end
		local reason = eventReason(event, "RebirthUnavailable")
		return result(true, nil, state("Idle", current.CycleId, reason), {
			Kind = "NotifyRejected",
			CycleId = current.CycleId,
			Reason = reason,
		})
	end

	if event.Kind == "Confirm" then
		if current.Mode ~= "AwaitingConfirmation" then
			return rejected(current, "InvalidTransition")
		end
		return result(true, nil, state("Committing", current.CycleId, nil), {
			Kind = "CommitRebirth",
			CycleId = current.CycleId,
			Reason = nil,
		})
	end

	if event.Kind == "CommitSucceeded" then
		if current.Mode ~= "Committing" then
			return rejected(current, "InvalidTransition")
		end
		return result(true, nil, state("ReloadingRuntime", current.CycleId, nil), {
			Kind = "ReloadRuntime",
			CycleId = current.CycleId,
			Reason = nil,
		})
	end

	if event.Kind == "CommitFailed" then
		if current.Mode ~= "Committing" then
			return rejected(current, "InvalidTransition")
		end
		local reason = eventReason(event, "CommitFailed")
		return result(true, nil, state("Idle", current.CycleId, reason), {
			Kind = "NotifyFailed",
			CycleId = current.CycleId,
			Reason = reason,
		})
	end

	if event.Kind == "CommitUncertain" then
		if current.Mode ~= "Committing" then
			return rejected(current, "InvalidTransition")
		end
		local reason = eventReason(event, "CommitResultUncertain")
		return result(true, nil, state("RecoveryRequired", current.CycleId, reason), {
			Kind = "RecoverSession",
			CycleId = current.CycleId,
			Reason = reason,
		})
	end

	if event.Kind == "RuntimeReloadSucceeded" then
		if current.Mode ~= "ReloadingRuntime" then
			return rejected(current, "InvalidTransition")
		end
		return result(true, nil, state("Idle", current.CycleId, nil), {
			Kind = "NotifyCompleted",
			CycleId = current.CycleId,
			Reason = nil,
		})
	end

	if event.Kind == "RuntimeReloadFailed" then
		if current.Mode ~= "ReloadingRuntime" then
			return rejected(current, "InvalidTransition")
		end
		local reason = eventReason(event, "RuntimeReloadFailed")
		return result(true, nil, state("RecoveryRequired", current.CycleId, reason), {
			Kind = "RecoverSession",
			CycleId = current.CycleId,
			Reason = reason,
		})
	end

	return rejected(current, "UnknownEvent")
end

return RebirthStateMachine
