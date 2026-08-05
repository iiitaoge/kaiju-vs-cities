--[[
	职责：把现有攻击选择 HUD 适配到正式攻击选择会话。
	输入：Open 接收 SpawnPointId 和怪兽管理回调；Start 初始化隐藏状态。
	输出：与 PlayerMonsterAttackSelectionCoordinator 相同的攻击选择会话，失败返回 nil。
	内部算法：选择中显示目标浏览区，Exit 取消；接受后隐藏浏览区并保留 Exit，Exit 只恢复跟随视角；跟随结束后清理。
	不负责：查询目标、相机算法、领地点选、服务器攻击校验或取消已接受的攻击。
]]

local Players = game:GetService("Players")

local LocalAttackSelectionHUDAccess = require(
	script.Parent.LocalAttackSelectionHUDAccess
)
local PlayerMonsterAttackSelectionCoordinator = require(
	script.Parent.PlayerMonsterAttackSelectionCoordinator
)

local AttackSelectionHUDController = {}

local started = false

local function resolveHUD(): (LocalAttackSelectionHUDAccess.References?, string?)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil, "PlayerGuiUnavailable"
	end
	return LocalAttackSelectionHUDAccess.Resolve(playerGui)
end

function AttackSelectionHUDController.Start()
	if started then
		return
	end
	started = true

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	playerGui:WaitForChild("HUD", 10)
	local refs, reason = LocalAttackSelectionHUDAccess.Resolve(playerGui)
	if not refs then
		warn("攻击选择 HUD 无效：" .. tostring(reason))
		return
	end
	refs.Root.Visible = false
	refs.BrowseControls.Visible = true
end

function AttackSelectionHUDController.Open(spawnPointId: string, callbacks)
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 无效")
	assert(type(callbacks) == "table", "callbacks 必须是 table")
	assert(type(callbacks.OnAccepted) == "function", "OnAccepted 必须是 function")
	assert(type(callbacks.OnCancelled) == "function", "OnCancelled 必须是 function")
	assert(type(callbacks.OnUnavailable) == "function", "OnUnavailable 必须是 function")

	local refs, reason = resolveHUD()
	if not refs then
		callbacks.OnUnavailable(reason or "AttackSelectionHUDUnavailable")
		return nil
	end

	refs.Root.Visible = false
	refs.BrowseControls.Visible = true
	local connections: { RBXScriptConnection } = {}
	local closed = false
	local following = false
	local session = nil

	local function cleanup()
		if closed then
			return
		end
		closed = true
		following = false
		refs.Root.Visible = false
		refs.BrowseControls.Visible = true
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end

	session = PlayerMonsterAttackSelectionCoordinator.Open(spawnPointId, {
		OnAccepted = function()
			if not following then
				cleanup()
			end
			callbacks.OnAccepted()
		end,
		OnCancelled = function()
			cleanup()
			callbacks.OnCancelled()
		end,
		OnUnavailable = function(unavailableReason)
			cleanup()
			callbacks.OnUnavailable(unavailableReason)
		end,
		OnTargetChanged = function(target)
			if closed then
				return
			end
			local solo = target.Kind == "Solo"
			refs.BrowseControls.Visible = not solo
			refs.Title.Text = if solo then target.DisplayName else target.Player.Name
			refs.Root.Visible = true
			if callbacks.OnTargetChanged then
				callbacks.OnTargetChanged(target)
			end
		end,
		OnValidationFailed = callbacks.OnValidationFailed,
		OnClosed = function(closeReason)
			if closeReason == "CommandAccepted" then
				refs.BrowseControls.Visible = false
				refs.Root.Visible = true
			else
				cleanup()
			end
			if callbacks.OnClosed then
				callbacks.OnClosed(closeReason)
			end
		end,
		OnFollowStarted = function(monster)
			if closed then
				return
			end
			following = true
			refs.BrowseControls.Visible = false
			refs.Root.Visible = true
			if callbacks.OnFollowStarted then
				callbacks.OnFollowStarted(monster)
			end
		end,
		OnFollowStopped = function(reason)
			cleanup()
			if callbacks.OnFollowStopped then
				callbacks.OnFollowStopped(reason)
			end
		end,
	})

	if not session then
		cleanup()
		return nil
	end

	table.insert(connections, refs.PreviousButton.Activated:Connect(function()
		if not closed and session.IsOpen() then
			session.PreviousTarget()
		end
	end))
	table.insert(connections, refs.NextButton.Activated:Connect(function()
		if not closed and session.IsOpen() then
			session.NextTarget()
		end
	end))
	table.insert(connections, refs.ExitButton.Activated:Connect(function()
		if closed then
			return
		end
		if session.IsOpen() then
			session.Cancel()
		elseif following and not session.RestoreCamera() then
			cleanup()
		end
	end))

	return session
end

return AttackSelectionHUDController
