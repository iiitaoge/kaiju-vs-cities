--[[
	职责：描述无 GUI、网络、相机依赖的攻击目标选择状态。

	输入：当前 State 和一个 Event。
	输出：Accepted、Reason、新 State，以及最多一个待协调 Effect。
	内部算法：维护稳定 TargetPlayerId 数组和当前索引，只按显式转换处理查询、切换、提交与关闭。

	不负责：获取 Player、查询 Remote、校验领地、监听输入、切换相机或执行攻击。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local MonsterAttackSelectionStateMachine = {}

export type Mode = "Closed" | "LoadingTargets" | "Browsing" | "Submitting" | "Unavailable"

export type State = {
	Mode: Mode,
	SpawnPointId: string?,
	TargetPlayerIds: { number },
	CurrentIndex: number,
	LastReason: string?,
}

export type Effect = {
	Kind: "QueryTargets" | "TargetChanged" | "RequestAttack" | "NotifyAccepted" | "CloseSelection",
	SpawnPointId: string?,
	TargetPlayerId: number?,
	EntryPoint: Vector3?,
	Result: any?,
	Reason: string?,
}

export type TransitionResult = {
	Accepted: boolean,
	Reason: string?,
	State: State,
	Effect: Effect?,
}

local function state(
	mode: Mode,
	spawnPointId: string?,
	targetPlayerIds: { number },
	currentIndex: number,
	lastReason: string?
): State
	return {
		Mode = mode,
		SpawnPointId = spawnPointId,
		TargetPlayerIds = table.clone(targetPlayerIds),
		CurrentIndex = currentIndex,
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

local function rejected(current: State, reason: string): TransitionResult
	return result(
		false,
		reason,
		state(
			current.Mode,
			current.SpawnPointId,
			current.TargetPlayerIds,
			current.CurrentIndex,
			reason
		),
		nil
	)
end

local function isPlayerId(value): boolean
	return type(value) == "number"
		and value == value
		and math.abs(value) < math.huge
		and value % 1 == 0
		and value ~= 0
end

local function normalizeTargetIds(values): { number }?
	if type(values) ~= "table" then
		return nil
	end
	local ids = {}
	local seen = {}
	for _, value in values do
		if isPlayerId(value) and not seen[value] then
			seen[value] = true
			table.insert(ids, value)
		end
	end
	table.sort(ids)
	return ids
end

local function currentTargetPlayerId(current: State): number?
	return current.TargetPlayerIds[current.CurrentIndex]
end

function MonsterAttackSelectionStateMachine.New(): State
	return state("Closed", nil, {}, 0, nil)
end

-- 支持的 Event.Kind：Open、TargetsLoaded、TargetsFailed、NextTarget、PreviousTarget、
-- Refresh、SubmitRequested、SubmitAccepted、SubmitRejected、TargetUnavailable、Cancel。
function MonsterAttackSelectionStateMachine.Apply(current: State, event): TransitionResult
	if type(current) ~= "table" or type(event) ~= "table" or type(event.Kind) ~= "string" then
		return rejected(MonsterAttackSelectionStateMachine.New(), "InvalidEvent")
	end

	if event.Kind == "Cancel" then
		if current.Mode == "Closed" then
			return result(true, nil, MonsterAttackSelectionStateMachine.New(), nil)
		end
		return result(true, nil, MonsterAttackSelectionStateMachine.New(), {
			Kind = "CloseSelection",
			SpawnPointId = current.SpawnPointId,
			Reason = "Cancelled",
		})
	end

	if event.Kind == "Open" then
		if current.Mode ~= "Closed" then
			return rejected(current, "SelectionAlreadyOpen")
		end
		if type(event.SpawnPointId) ~= "string" or event.SpawnPointId == "" then
			return rejected(current, "InvalidSpawnPointId")
		end
		local nextState = state("LoadingTargets", event.SpawnPointId, {}, 0, nil)
		return result(true, nil, nextState, {
			Kind = "QueryTargets",
			SpawnPointId = event.SpawnPointId,
		})
	end

	local spawnPointId = current.SpawnPointId
	if not spawnPointId then
		return rejected(current, "SelectionClosed")
	end

	if event.Kind == "TargetsLoaded" then
		if current.Mode ~= "LoadingTargets" then
			return rejected(current, "InvalidTransition")
		end
		local ids = normalizeTargetIds(event.TargetPlayerIds)
		if not ids then
			return rejected(current, "InvalidTargets")
		end
		if #ids == 0 then
			return result(true, nil, state("Unavailable", spawnPointId, {}, 0, "TargetUnavailable"), {
				Kind = "TargetChanged",
				SpawnPointId = spawnPointId,
				TargetPlayerId = nil,
				Reason = "TargetUnavailable",
			})
		end

		local previousTargetPlayerId = currentTargetPlayerId(current)
		local nextIndex = 1
		if previousTargetPlayerId then
			for index, targetPlayerId in ids do
				if targetPlayerId == previousTargetPlayerId then
					nextIndex = index
					break
				end
			end
		end
		return result(true, nil, state("Browsing", spawnPointId, ids, nextIndex, nil), {
			Kind = "TargetChanged",
			SpawnPointId = spawnPointId,
			TargetPlayerId = ids[nextIndex],
		})
	end

	if event.Kind == "TargetsFailed" then
		if current.Mode ~= "LoadingTargets" then
			return rejected(current, "InvalidTransition")
		end
		local reason = if type(event.Reason) == "string" and event.Reason ~= ""
			then event.Reason
			else "TargetQueryFailed"
		return result(true, nil, state("Unavailable", spawnPointId, {}, 0, reason), {
			Kind = "TargetChanged",
			SpawnPointId = spawnPointId,
			TargetPlayerId = nil,
			Reason = reason,
		})
	end

	if event.Kind == "Refresh" then
		if current.Mode ~= "Browsing" and current.Mode ~= "Unavailable" then
			return rejected(current, "InvalidTransition")
		end
		return result(
			true,
			nil,
			state(
				"LoadingTargets",
				spawnPointId,
				current.TargetPlayerIds,
				current.CurrentIndex,
				nil
			),
			{
				Kind = "QueryTargets",
				SpawnPointId = spawnPointId,
			}
		)
	end

	if event.Kind == "NextTarget" or event.Kind == "PreviousTarget" then
		if current.Mode ~= "Browsing" or #current.TargetPlayerIds == 0 then
			return rejected(current, "TargetUnavailable")
		end
		local delta = if event.Kind == "NextTarget" then 1 else -1
		local nextIndex = ((current.CurrentIndex - 1 + delta) % #current.TargetPlayerIds) + 1
		return result(
			true,
			nil,
			state("Browsing", spawnPointId, current.TargetPlayerIds, nextIndex, nil),
			{
				Kind = "TargetChanged",
				SpawnPointId = spawnPointId,
				TargetPlayerId = current.TargetPlayerIds[nextIndex],
			}
		)
	end

	if event.Kind == "TargetUnavailable" then
		if current.Mode ~= "Browsing" then
			return rejected(current, "InvalidTransition")
		end
		local unavailableId = if isPlayerId(event.TargetPlayerId)
			then event.TargetPlayerId
			else currentTargetPlayerId(current)
		local remaining = {}
		for _, targetPlayerId in current.TargetPlayerIds do
			if targetPlayerId ~= unavailableId then
				table.insert(remaining, targetPlayerId)
			end
		end
		if #remaining == 0 then
			return result(true, nil, state("Unavailable", spawnPointId, {}, 0, "TargetUnavailable"), {
				Kind = "TargetChanged",
				SpawnPointId = spawnPointId,
				TargetPlayerId = nil,
				Reason = "TargetUnavailable",
			})
		end
		local nextIndex = math.min(current.CurrentIndex, #remaining)
		return result(true, nil, state("Browsing", spawnPointId, remaining, nextIndex, nil), {
			Kind = "TargetChanged",
			SpawnPointId = spawnPointId,
			TargetPlayerId = remaining[nextIndex],
		})
	end

	if event.Kind == "SubmitRequested" then
		if current.Mode ~= "Browsing" then
			return rejected(current, if current.Mode == "Submitting" then "RequestBusy" else "TargetUnavailable")
		end
		local targetPlayerId = currentTargetPlayerId(current)
		if not targetPlayerId then
			return rejected(current, "TargetUnavailable")
		end
		if not ValueValidation.IsFiniteVector3(event.EntryPoint) then
			return rejected(current, "InvalidEntryPoint")
		end
		return result(
			true,
			nil,
			state(
				"Submitting",
				spawnPointId,
				current.TargetPlayerIds,
				current.CurrentIndex,
				nil
			),
			{
				Kind = "RequestAttack",
				SpawnPointId = spawnPointId,
				TargetPlayerId = targetPlayerId,
				EntryPoint = event.EntryPoint,
			}
		)
	end

	if event.Kind == "SubmitRejected" then
		if current.Mode ~= "Submitting" and current.Mode ~= "Browsing" then
			return rejected(current, "InvalidTransition")
		end
		local reason = if type(event.Reason) == "string" and event.Reason ~= ""
			then event.Reason
			else "CommandRejected"
		return result(
			true,
			nil,
			state(
				"Browsing",
				spawnPointId,
				current.TargetPlayerIds,
				current.CurrentIndex,
				reason
			),
			nil
		)
	end

	if event.Kind == "SubmitAccepted" then
		if current.Mode ~= "Submitting" then
			return rejected(current, "InvalidTransition")
		end
		local targetPlayerId = currentTargetPlayerId(current)
		return result(true, nil, MonsterAttackSelectionStateMachine.New(), {
			Kind = "NotifyAccepted",
			SpawnPointId = spawnPointId,
			TargetPlayerId = targetPlayerId,
			Result = event.Result,
			Reason = "CommandAccepted",
		})
	end

	return rejected(current, "UnknownEvent")
end

return MonsterAttackSelectionStateMachine
