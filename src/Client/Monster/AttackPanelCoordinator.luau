local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterAttackSelectionStateMachine = require(
	ReplicatedStorage.Shared.Monster.MonsterAttackSelectionStateMachine
)
local TerritoryPointRules = require(ReplicatedStorage.Shared.Monster.TerritoryPointRules)

local AttackPanelCoordinator = {}

export type Territory = {
	ZoneId: string,
	BoundsId: string,
	CFrame: CFrame,
	Size: Vector3,
	AttackInProgress: boolean,
}

export type AttackView = {
	CFrame: CFrame,
	Size: Vector3,
}

export type Target = {
	Player: Player,
	UnlockedTerritories: { Territory },
	AttackView: AttackView,
}

export type RequestResult = {
	Succeeded: boolean,
	Reason: string?,
	CommandId: number?,
	Monster: Model?,
}

export type OpenOptions = {
	LocalPlayer: Player,
	GetTargets: () -> { Target },
	RequestAttack: (string, Player, Vector3) -> RequestResult,
	OnTargetChanged: (Target) -> (),
	OnTargetUnavailable: () -> (),
	OnValidationFailed: (string) -> (),
	OnAccepted: (RequestResult, Target) -> (),
	OnClosed: (string) -> (),
}

export type Session = {
	NextTarget: () -> Target?,
	PreviousTarget: () -> Target?,
	RefreshTargets: () -> Target?,
	ValidateWorldPoint: (Vector3) -> (boolean, string?),
	SubmitWorldPoint: (Vector3) -> RequestResult,
	Cancel: () -> (),
	GetCurrentTarget: () -> Target?,
	IsOpen: () -> boolean,
}

local function failure(reason: string): RequestResult
	return {
		Succeeded = false,
		Reason = reason,
		CommandId = nil,
		Monster = nil,
	}
end

local function eligibleTargets(localPlayer: Player, values: { Target }): { Target }
	local result = {}
	for _, target in values do
		if type(target) == "table"
			and typeof(target.Player) == "Instance"
			and target.Player:IsA("Player")
			and target.Player ~= localPlayer
			and target.Player.Parent == Players then
			table.insert(result, target)
		end
	end
	table.sort(result, function(a, b)
		return a.Player.UserId < b.Player.UserId
	end)
	return result
end

-- 输入：已选怪兽出生点和 UI/网络适配回调。
-- 输出：供按钮和屏幕点击调用的面板会话。
-- 内部算法：纯状态机决定查询/切换/提交/关闭；本协调器只执行 Effect、领地规则和回调。
function AttackPanelCoordinator.Open(
	spawnPointId: string,
	options: OpenOptions
): Session
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 无效")
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.GetTargets) == "function", "GetTargets 必须是 function")
	assert(type(options.RequestAttack) == "function", "RequestAttack 必须是 function")
	assert(type(options.OnTargetChanged) == "function", "OnTargetChanged 必须是 function")
	assert(type(options.OnTargetUnavailable) == "function", "OnTargetUnavailable 必须是 function")
	assert(type(options.OnValidationFailed) == "function", "OnValidationFailed 必须是 function")
	assert(type(options.OnAccepted) == "function", "OnAccepted 必须是 function")
	assert(type(options.OnClosed) == "function", "OnClosed 必须是 function")

	local current = MonsterAttackSelectionStateMachine.New()
	local targetsByUserId: { [number]: Target } = {}
	local dispatch

	local function currentTarget(): Target?
		local targetPlayerId = current.TargetPlayerIds[current.CurrentIndex]
		return if targetPlayerId then targetsByUserId[targetPlayerId] else nil
	end

	local function queryTargets()
		local succeeded, valuesOrError = pcall(options.GetTargets)
		if not succeeded or type(valuesOrError) ~= "table" then
			targetsByUserId = {}
			dispatch({
				Kind = "TargetsFailed",
				Reason = if succeeded then "InvalidTargets" else "TargetQueryFailed",
			})
			return
		end

		local nextTargetsByUserId = {}
		local targetPlayerIds = {}
		for _, target in eligibleTargets(options.LocalPlayer, valuesOrError) do
			nextTargetsByUserId[target.Player.UserId] = target
			table.insert(targetPlayerIds, target.Player.UserId)
		end
		targetsByUserId = nextTargetsByUserId
		dispatch({
			Kind = "TargetsLoaded",
			TargetPlayerIds = targetPlayerIds,
		})
	end

	local function checkWorldPoint(target: Target, worldPoint: Vector3): (boolean, string?)
		local allowed = false
		local validTerritoryCount = 0
		local invalidPointReason = nil
		for _, territory in target.UnlockedTerritories do
			local pointCheck = TerritoryPointRules.Check(
				territory.CFrame,
				territory.Size,
				worldPoint
			)
			if pointCheck.Reason == "InvalidEntryPoint" then
				invalidPointReason = pointCheck.Reason
				break
			end
			if pointCheck.Reason ~= "InvalidTerritory" then
				validTerritoryCount += 1
			end
			if pointCheck.Allowed then
				if territory.AttackInProgress then
					return false, "RegionAttackInProgress"
				end
				allowed = true
				break
			end
		end
		if allowed then
			return true, nil
		end
		return false, invalidPointReason
			or if validTerritoryCount > 0
				then "EntryPointOutsideTerritory"
				else "TargetTerritoryUnavailable"
	end

	local function runRequest(effect): RequestResult
		local targetPlayerId = effect.TargetPlayerId
		local target = if targetPlayerId then targetsByUserId[targetPlayerId] else nil
		if not target or target.Player.Parent ~= Players then
			local result = failure("TargetUnavailable")
			dispatch({ Kind = "SubmitRejected", Reason = result.Reason })
			if targetPlayerId then
				dispatch({ Kind = "TargetUnavailable", TargetPlayerId = targetPlayerId })
			else
				options.OnTargetUnavailable()
			end
			return result
		end

		local succeeded, resultOrError = pcall(
			options.RequestAttack,
			effect.SpawnPointId,
			target.Player,
			effect.EntryPoint
		)
		if not succeeded then
			local result = failure("RequestFailed")
			dispatch({ Kind = "SubmitRejected", Reason = result.Reason })
			options.OnValidationFailed(result.Reason)
			return result
		end
		if type(resultOrError) ~= "table" or type(resultOrError.Succeeded) ~= "boolean" then
			local result = failure("InvalidServerResponse")
			dispatch({ Kind = "SubmitRejected", Reason = result.Reason })
			options.OnValidationFailed(result.Reason)
			return result
		end

		local result = resultOrError :: RequestResult
		if not result.Succeeded then
			local reason = result.Reason or "CommandRejected"
			dispatch({ Kind = "SubmitRejected", Reason = reason })
			options.OnValidationFailed(reason)
			return result
		end
		dispatch({ Kind = "SubmitAccepted", Result = result })
		return result
	end

	local function runEffect(effect)
		if effect.Kind == "QueryTargets" then
			queryTargets()
			return nil
		end
		if effect.Kind == "TargetChanged" then
			local target = if effect.TargetPlayerId
				then targetsByUserId[effect.TargetPlayerId]
				else nil
			if target then
				options.OnTargetChanged(target)
			else
				options.OnTargetUnavailable()
			end
			return target
		end
		if effect.Kind == "RequestAttack" then
			return runRequest(effect)
		end
		if effect.Kind == "NotifyAccepted" then
			local target = if effect.TargetPlayerId
				then targetsByUserId[effect.TargetPlayerId]
				else nil
			local requestResult = effect.Result :: RequestResult
			options.OnClosed(effect.Reason or "CommandAccepted")
			if target then
				options.OnAccepted(requestResult, target)
			else
				options.OnTargetUnavailable()
			end
			return requestResult
		end
		if effect.Kind == "CloseSelection" then
			options.OnClosed(effect.Reason or "Cancelled")
		end
		return nil
	end

	local function validateWorldPoint(worldPoint: Vector3): (boolean, string?)
		if current.Mode == "Closed" then
			return false, "PanelClosed"
		end
		if current.Mode == "LoadingTargets" or current.Mode == "Submitting" then
			return false, "RequestBusy"
		end
		local target = currentTarget()
		if current.Mode ~= "Browsing" or not target then
			return false, "TargetUnavailable"
		end
		if target.Player.Parent ~= Players then
			return false, "TargetUnavailable"
		end
		return checkWorldPoint(target, worldPoint)
	end

	dispatch = function(event)
		local transition = MonsterAttackSelectionStateMachine.Apply(current, event)
		current = transition.State
		local effectResult = nil
		if transition.Accepted and transition.Effect then
			effectResult = runEffect(transition.Effect)
		end
		return transition, effectResult
	end

	local opened = dispatch({ Kind = "Open", SpawnPointId = spawnPointId })
	assert(opened.Accepted, opened.Reason or "攻击选择状态机打开失败")

	local function shift(kind: "NextTarget" | "PreviousTarget"): Target?
		local transition = dispatch({ Kind = kind })
		if not transition.Accepted then
			if transition.Reason == "TargetUnavailable" then
				options.OnTargetUnavailable()
			end
			return nil
		end
		return currentTarget()
	end

	local function refresh(): Target?
		local transition = dispatch({ Kind = "Refresh" })
		return if transition.Accepted then currentTarget() else nil
	end

	local function submit(worldPoint: Vector3): RequestResult
		if current.Mode == "Closed" then
			return failure("PanelClosed")
		end
		if current.Mode == "LoadingTargets" or current.Mode == "Submitting" then
			return failure("RequestBusy")
		end
		local target = currentTarget()
		if current.Mode ~= "Browsing" or not target then
			options.OnTargetUnavailable()
			return failure("TargetUnavailable")
		end
		if target.Player.Parent ~= Players then
			dispatch({
				Kind = "TargetUnavailable",
				TargetPlayerId = target.Player.UserId,
			})
			return failure("TargetUnavailable")
		end

		local allowed, invalidPointReason = checkWorldPoint(target, worldPoint)
		if not allowed then
			local reason = invalidPointReason or "TargetTerritoryUnavailable"
			dispatch({ Kind = "SubmitRejected", Reason = reason })
			options.OnValidationFailed(reason)
			return failure(reason)
		end

		local transition, effectResult = dispatch({
			Kind = "SubmitRequested",
			EntryPoint = worldPoint,
		})
		if not transition.Accepted then
			local reason = transition.Reason or "CommandRejected"
			options.OnValidationFailed(reason)
			return failure(reason)
		end
		return effectResult or failure("InvalidServerResponse")
	end

	return {
		NextTarget = function()
			return shift("NextTarget")
		end,
		PreviousTarget = function()
			return shift("PreviousTarget")
		end,
		RefreshTargets = refresh,
		ValidateWorldPoint = validateWorldPoint,
		SubmitWorldPoint = submit,
		Cancel = function()
			if current.Mode ~= "Closed" then
				dispatch({ Kind = "Cancel" })
			end
		end,
		GetCurrentTarget = currentTarget,
		IsOpen = function()
			return current.Mode ~= "Closed"
		end,
	}
end

return AttackPanelCoordinator
