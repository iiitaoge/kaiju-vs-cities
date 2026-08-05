--[[
	职责：管理没有其他玩家时的单人空地选点会话。
	输入：自己的 SpawnPointId、单人目标快照和网络/UI 回调。
	输出：与正式攻击面板兼容的提交、取消和查询会话。
	内部算法：只允许 SoloAttackBounds 内的世界点；服务器拒绝后保持打开，接受后关闭。
	不负责：查询玩家、相机、准星、怪兽移动、动画或奖励。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TerritoryPointRules = require(
	ReplicatedStorage.Shared.Monster.TerritoryPointRules
)

local SoloAttackPanelCoordinator = {}

export type Territory = {
	ZoneId: string,
	BoundsId: string,
	CFrame: CFrame,
	Size: Vector3,
}

export type Target = {
	Kind: "Solo",
	DisplayName: string,
	AttackView: {
		CFrame: CFrame,
		Size: Vector3,
	},
	UnlockedTerritories: { Territory },
}

local function failure(reason: string)
	return {
		Succeeded = false,
		Reason = reason,
		CommandId = nil,
		Monster = nil,
	}
end

function SoloAttackPanelCoordinator.Open(spawnPointId: string, target: Target, options)
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 无效")
	assert(type(target) == "table" and target.Kind == "Solo", "target 无效")
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.RequestAttack) == "function", "RequestAttack 必须是 function")
	assert(type(options.OnValidationFailed) == "function", "OnValidationFailed 必须是 function")
	assert(type(options.OnAccepted) == "function", "OnAccepted 必须是 function")
	assert(type(options.OnClosed) == "function", "OnClosed 必须是 function")

	local open = true
	local submitting = false

	local function submit(worldPoint: Vector3)
		if not open then
			return failure("PanelClosed")
		end
		if submitting then
			return failure("RequestBusy")
		end
		local bounds = target.UnlockedTerritories[1]
		local pointCheck = if bounds
			then TerritoryPointRules.Check(bounds.CFrame, bounds.Size, worldPoint)
			else { Allowed = false, Reason = "SoloAttackBoundsUnavailable" }
		if not pointCheck.Allowed then
			local reason = pointCheck.Reason or "EntryPointOutsideTerritory"
			options.OnValidationFailed(reason)
			return failure(reason)
		end

		submitting = true
		local succeeded, responseOrError = pcall(
			options.RequestAttack,
			spawnPointId,
			worldPoint
		)
		submitting = false
		if not succeeded then
			options.OnValidationFailed("RequestFailed")
			return failure("RequestFailed")
		end
		if type(responseOrError) ~= "table"
			or type(responseOrError.Succeeded) ~= "boolean" then
			options.OnValidationFailed("InvalidServerResponse")
			return failure("InvalidServerResponse")
		end
		if not responseOrError.Succeeded then
			local reason = responseOrError.Reason or "CommandRejected"
			options.OnValidationFailed(reason)
			return responseOrError
		end

		open = false
		options.OnClosed("CommandAccepted")
		options.OnAccepted(responseOrError, target)
		return responseOrError
	end

	return {
		NextTarget = function()
			return if open then target else nil
		end,
		PreviousTarget = function()
			return if open then target else nil
		end,
		RefreshTargets = function()
			return if open then target else nil
		end,
		SubmitWorldPoint = submit,
		Cancel = function()
			if open then
				open = false
				options.OnClosed("Cancelled")
			end
		end,
		GetCurrentTarget = function()
			return if open then target else nil
		end,
		IsOpen = function()
			return open
		end,
	}
end

return SoloAttackPanelCoordinator
