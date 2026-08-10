--[[
	职责：把现有 StarterGui.PopUp.InCombat.Check.Button 接到防守玩家的决斗观看开关。
	输入：服务端 DuelAvailable/DuelFocus/DuelRestore 命令和按钮点击。
	输出：按钮显示、观看/退出文案和 ToggleDuelCamera 请求。
	不负责：验证战斗身份、判断胜负或直接控制 CurrentCamera。
]]

local Players = game:GetService("Players")

local MonsterDuelCameraProtocol = require(
	game:GetService("ReplicatedStorage").Shared.Monster.MonsterDuelCameraProtocol
)
local MonsterDuelCameraRemoteClient = require(script.Parent.MonsterDuelCameraRemoteClient)
local LocalGuiButtonState = require(
	script.Parent.Parent.UI.LocalGuiButtonState
)

local MonsterDuelWatchButtonController = {}

type References = {
	Root: Frame,
	Check: Frame,
	Button: TextButton,
	Value: TextLabel?,
}

local started = false
local references: References? = nil
local activeCommand: MonsterDuelCameraProtocol.CameraCommand? = nil
local watching = false
local pendingCommand: MonsterDuelCameraProtocol.CameraCommand? = nil
local togglePending = false
local buttonConnection: RBXScriptConnection? = nil

local function childOfClass(parent: Instance?, name: string, className: string): Instance?
	local child = parent and parent:FindFirstChild(name)
	return if child and child:IsA(className) then child else nil
end

local function resolve(playerGui: PlayerGui): References?
	local popup = childOfClass(playerGui, "PopUp", "ScreenGui")
	local root = childOfClass(popup, "InCombat", "Frame")
	local check = childOfClass(root, "Check", "Frame")
	local button = childOfClass(check, "Button", "TextButton")
	local info = childOfClass(button, "Info", "Frame")
	local value = childOfClass(info, "Val", "TextLabel")
	if not root or not check or not button then
		return nil
	end
	return {
		Root = root,
		Check = check,
		Button = button,
		Value = value :: TextLabel?,
	}
end

local function setVisible(visible: boolean)
	local current = references
	if not current then
		return
	end
	current.Root.Visible = visible
	current.Check.Visible = visible
	current.Button.Visible = visible
	LocalGuiButtonState.SetEnabled(current.Button, visible and not togglePending)
end

local function setText(text: string)
	local current = references
	if current and current.Value then
		current.Value.Text = text
	end
end

local function hide()
	activeCommand = nil
	pendingCommand = nil
	togglePending = false
	watching = false
	setVisible(false)
	setText("Watch Duel")
end

local function show(command: MonsterDuelCameraProtocol.CameraCommand)
	activeCommand = command
	pendingCommand = nil
	togglePending = false
	watching = false
	setText("Watch Duel")
	setVisible(true)
end

local function bindGui(playerGui: PlayerGui)
	local resolved = resolve(playerGui)
	if not resolved then
		return
	end
	local commandToRestore = activeCommand or pendingCommand
	if buttonConnection then
		buttonConnection:Disconnect()
		buttonConnection = nil
	end
	references = resolved
	hide()
	buttonConnection = resolved.Button.Activated:Connect(function()
		local command = activeCommand
		if not command or togglePending then
			return
		end
		togglePending = true
		LocalGuiButtonState.SetEnabled(resolved.Button, false)
		local previousWatching = watching
		watching = not watching
		setText("Updating...")
		local sent = MonsterDuelCameraRemoteClient.RequestToggle(
			command.DuelId,
			watching
		)
		if activeCommand ~= command then
			return
		end
		togglePending = false
		if not sent then
			watching = previousWatching
		end
		setText(if watching then "Stop Watching" else "Watch Duel")
		LocalGuiButtonState.SetEnabled(resolved.Button, true)
	end)
	if commandToRestore then
		show(commandToRestore)
	end
end

function MonsterDuelWatchButtonController.Start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	bindGui(playerGui)
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "PopUp" and child:IsA("ScreenGui") then
			task.defer(function()
				bindGui(playerGui)
			end)
		end
	end)
	MonsterDuelCameraRemoteClient.Observe(function(command)
		if command.Kind == MonsterDuelCameraProtocol.AvailableKind then
			if references then
				show(command)
			else
				pendingCommand = command
			end
		elseif command.Kind == MonsterDuelCameraProtocol.FocusKind then
			if activeCommand and activeCommand.DuelId == command.DuelId then
				watching = true
				setText("Stop Watching")
			end
		elseif command.Kind == MonsterDuelCameraProtocol.RestoreKind then
			if activeCommand and activeCommand.DuelId == command.DuelId then
				hide()
			end
		end
	end)
end

return MonsterDuelWatchButtonController
