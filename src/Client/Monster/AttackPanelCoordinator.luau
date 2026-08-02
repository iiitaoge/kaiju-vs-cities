local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TerritoryPointRules = require(ReplicatedStorage.Shared.Monster.TerritoryPointRules)

local AttackPanelCoordinator = {}

export type Territory = {
	ZoneId: string,
	BoundsId: string,
	CFrame: CFrame,
	Size: Vector3,
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
	SubmitWorldPoint: (Vector3) -> RequestResult,
	Cancel: () -> (),
	GetCurrentTarget: () -> Target?,
	IsOpen: () -> boolean,
}

local function eligibleTargets(localPlayer: Player, values: { Target }): { Target }
	local result = {}
	for _, target in values do
		if target.Player ~= localPlayer and target.Player.Parent == Players then
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
-- 内部算法：维护稳定目标玩家索引，切换时通知镜头；坐标先本地校验，再提交服务器。
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

	local open = true
	local busy = false
	local targets: { Target } = {}
	local index = 0

	local function current(): Target?
		return if index >= 1 and index <= #targets then targets[index] else nil
	end

	local function notifyCurrent(): Target?
		local target = current()
		if target then
			options.OnTargetChanged(target)
		else
			options.OnTargetUnavailable()
		end
		return target
	end

	local function reload(notify: boolean): Target?
		if not open then
			return nil
		end
		local previous = current()
		targets = eligibleTargets(options.LocalPlayer, options.GetTargets())
		index = 0
		if previous then
			for targetIndex, target in targets do
				if target.Player.UserId == previous.Player.UserId then
					index = targetIndex
					break
				end
			end
		end
		if index == 0 and #targets > 0 then
			index = 1
		end
		return if notify then notifyCurrent() else current()
	end

	local function refresh(): Target?
		return reload(true)
	end

	local function shift(delta: number): Target?
		if not open then
			return nil
		end
		reload(false)
		if #targets == 0 then
			options.OnTargetUnavailable()
			return nil
		end
		index = ((index - 1 + delta) % #targets) + 1
		return notifyCurrent()
	end

	local function close(reason: string)
		if not open then
			return
		end
		open = false
		options.OnClosed(reason)
	end

	local function submit(worldPoint: Vector3): RequestResult
		if not open then
			return { Succeeded = false, Reason = "PanelClosed", CommandId = nil, Monster = nil }
		end
		if busy then
			return { Succeeded = false, Reason = "RequestBusy", CommandId = nil, Monster = nil }
		end
		local target = current()
		if not target then
			options.OnTargetUnavailable()
			return { Succeeded = false, Reason = "TargetUnavailable", CommandId = nil, Monster = nil }
		end

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
				allowed = true
				break
			end
		end
		if not allowed then
			local reason = invalidPointReason
				or if validTerritoryCount > 0
					then "EntryPointOutsideTerritory"
					else "TargetTerritoryUnavailable"
			options.OnValidationFailed(reason)
			return { Succeeded = false, Reason = reason, CommandId = nil, Monster = nil }
		end

		busy = true
		local succeeded, resultOrError = pcall(
			options.RequestAttack,
			spawnPointId,
			target.Player,
			worldPoint
		)
		busy = false
		if not succeeded then
			options.OnValidationFailed("RequestFailed")
			return { Succeeded = false, Reason = "RequestFailed", CommandId = nil, Monster = nil }
		end
		if type(resultOrError) ~= "table" or type(resultOrError.Succeeded) ~= "boolean" then
			options.OnValidationFailed("InvalidServerResponse")
			return {
				Succeeded = false,
				Reason = "InvalidServerResponse",
				CommandId = nil,
				Monster = nil,
			}
		end
		local result = resultOrError :: RequestResult
		if not result.Succeeded then
			options.OnValidationFailed(result.Reason or "CommandRejected")
			return result
		end

		open = false
		options.OnClosed("CommandAccepted")
		options.OnAccepted(result, target)
		return result
	end

	refresh()
	return {
		NextTarget = function()
			return shift(1)
		end,
		PreviousTarget = function()
			return shift(-1)
		end,
		RefreshTargets = refresh,
		SubmitWorldPoint = submit,
		Cancel = function()
			close("Cancelled")
		end,
		GetCurrentTarget = current,
		IsOpen = function()
			return open
		end,
	}
end

return AttackPanelCoordinator
