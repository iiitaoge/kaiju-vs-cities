--[[
	职责：组装怪兽管理状态机、服务器请求和未来 GUI/攻击面板适配器。

	输入：Render、可选 Query/Upgrade、OpenAttackSelection 回调，以及会话期余额变化。
	输出：Open、ChooseUpgrade、ChooseAttack、UpdateBalance、Retry、Close、GetState 会话接口。
	内部算法：应用纯状态机 → 立即 Render → 异步执行 Effect → 把结果重新送回状态机。

	不负责：创建 ScreenGui、决定美术样式、选择目标玩家或提交攻击坐标。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManagementRemoteClient = require(script.Parent.MonsterManagementRemoteClient)
local MonsterManagementStateMachine = require(
	ReplicatedStorage.Shared.Monster.MonsterManagementStateMachine
)

local MonsterManagementCoordinator = {}

export type AttackCallbacks = {
	OnAccepted: () -> (),
	OnCancelled: () -> (),
	OnUnavailable: (string?) -> (),
}

export type AttackSession = {
	Cancel: () -> (),
}

export type Options = {
	Render: (MonsterManagementStateMachine.State) -> (),
	Query: ((string) -> any)?,
	Upgrade: ((string) -> any)?,
	OpenAttackSelection: ((string, AttackCallbacks) -> AttackSession?)?,
	OnInsufficientMoney: (() -> ())?,
	OnUpgradeResult: ((boolean, string?) -> ())?,
}

export type Session = {
	Open: (string) -> MonsterManagementStateMachine.TransitionResult,
	ChooseUpgrade: () -> MonsterManagementStateMachine.TransitionResult,
	ChooseAttack: () -> MonsterManagementStateMachine.TransitionResult,
	UpdateBalance: (number) -> MonsterManagementStateMachine.TransitionResult,
	Retry: () -> MonsterManagementStateMachine.TransitionResult,
	Close: () -> MonsterManagementStateMachine.TransitionResult,
	GetState: () -> MonsterManagementStateMachine.State,
}

function MonsterManagementCoordinator.Create(options: Options): Session
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.Render) == "function", "Render 必须是 function")
	local query = options.Query or MonsterManagementRemoteClient.GetSnapshot
	local upgrade = options.Upgrade or MonsterManagementRemoteClient.Upgrade
	assert(type(query) == "function", "Query 必须是 function")
	assert(type(upgrade) == "function", "Upgrade 必须是 function")

	local current = MonsterManagementStateMachine.New()
	local requestId = 0
	local attackSession: AttackSession? = nil
	local dispatch

	local function render()
		options.Render(current)
	end

	local function notifyInsufficientMoney(reason: string?)
		if reason == "InsufficientMoney" and options.OnInsufficientMoney then
			options.OnInsufficientMoney()
		end
	end

	local function nextRequestId(): number
		requestId += 1
		return requestId
	end

	local function runRequest(effect, requestFunction, resolvedKind: string)
		local function reportUpgradeResult(succeeded: boolean, reason: string?)
			if resolvedKind == "UpgradeResolved" and options.OnUpgradeResult then
				options.OnUpgradeResult(succeeded, reason)
			end
		end

		local ownRequestId = nextRequestId()
		task.spawn(function()
			local called, responseOrError = pcall(requestFunction, effect.SpawnPointId)
			if ownRequestId ~= requestId then
				return
			end
			if not called or type(responseOrError) ~= "table" then
				if resolvedKind == "SnapshotLoaded" then
					dispatch({
						Kind = "SnapshotFailed",
						Reason = if called then "InvalidServerResponse" else "RequestFailed",
					})
				else
					reportUpgradeResult(false, if called then "InvalidServerResponse" else "RequestFailed")
					dispatch({
						Kind = "UpgradeResolved",
						Succeeded = false,
						Reason = if called then "InvalidServerResponse" else "RequestFailed",
						Snapshot = nil,
					})
				end
				return
			end
			notifyInsufficientMoney(responseOrError.Reason)

			if resolvedKind == "SnapshotLoaded" then
				if responseOrError.Succeeded then
					dispatch({ Kind = "SnapshotLoaded", Snapshot = responseOrError.Snapshot })
				else
					dispatch({ Kind = "SnapshotFailed", Reason = responseOrError.Reason })
				end
			else
				reportUpgradeResult(
					responseOrError.Succeeded == true,
					responseOrError.Reason
				)
				dispatch({
					Kind = "UpgradeResolved",
					Succeeded = responseOrError.Succeeded == true,
					Reason = responseOrError.Reason,
					Snapshot = responseOrError.Snapshot,
				})
			end
		end)
	end

	local function runEffect(effect)
		if effect.Kind == "QuerySnapshot" then
			runRequest(effect, query, "SnapshotLoaded")
			return
		end
		if effect.Kind == "RequestUpgrade" then
			runRequest(effect, upgrade, "UpgradeResolved")
			return
		end
		if effect.Kind == "CloseAttackSelection" then
			local session = attackSession
			attackSession = nil
			if session then
				pcall(session.Cancel)
			end
			return
		end
		if effect.Kind ~= "OpenAttackSelection" then
			return
		end

		if type(options.OpenAttackSelection) ~= "function" then
			dispatch({ Kind = "AttackUnavailable", Reason = "AttackSelectionAdapterUnavailable" })
			return
		end
		local opened, sessionOrError = pcall(options.OpenAttackSelection, effect.SpawnPointId, {
			OnAccepted = function()
				if current.Mode == "SelectingAttack" then
					attackSession = nil
					dispatch({ Kind = "AttackAccepted" })
				end
			end,
			OnCancelled = function()
				if current.Mode == "SelectingAttack" then
					attackSession = nil
					dispatch({ Kind = "AttackCancelled" })
				end
			end,
			OnUnavailable = function(reason)
				if current.Mode == "SelectingAttack" then
					local session = attackSession
					attackSession = nil
					dispatch({ Kind = "AttackUnavailable", Reason = reason })
					if session then
						pcall(session.Cancel)
					end
				end
			end,
		})
		if not opened or type(sessionOrError) ~= "table" or type(sessionOrError.Cancel) ~= "function" then
			dispatch({ Kind = "AttackUnavailable", Reason = "AttackSelectionOpenFailed" })
			return
		end
		if current.Mode ~= "SelectingAttack" then
			pcall(sessionOrError.Cancel)
			return
		end
		attackSession = sessionOrError
	end

	dispatch = function(event)
		local transition = MonsterManagementStateMachine.Apply(current, event)
		current = transition.State
		render()
		if transition.Effect then
			runEffect(transition.Effect)
		end
		return transition
	end

	render()
	return {
		Open = function(spawnPointId: string)
			requestId += 1
			return dispatch({ Kind = "Open", SpawnPointId = spawnPointId })
		end,
		ChooseUpgrade = function()
			local transition = dispatch({ Kind = "ChooseUpgrade" })
			notifyInsufficientMoney(transition.Reason)
			return transition
		end,
		ChooseAttack = function()
			return dispatch({ Kind = "ChooseAttack" })
		end,
		UpdateBalance = function(balance: number)
			return dispatch({ Kind = "BalanceChanged", Balance = balance })
		end,
		Retry = function()
			return dispatch({ Kind = "Retry" })
		end,
		Close = function()
			requestId += 1
			return dispatch({ Kind = "Close" })
		end,
		GetState = function()
			return current
		end,
	}
end

return MonsterManagementCoordinator
