--[[
	职责：在 Studio Play 中创建一键删除当前测试玩家存档的 UI。
	输入：Start 无参数；玩家点击按钮。
	输出：按钮展示处理中/成功/失败；成功后服务器退出当前玩家。
	内部算法：Studio 门禁 → 按桌面/触屏位置创建单按钮 ScreenGui → 调用 StudioSaveReset RemoteFunction。
	不负责：选择 UserId、DataStore、保存会话或正式服 UI。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local StudioSaveResetProtocol = require(
	ReplicatedStorage.Shared.Persistence.StudioSaveResetProtocol
)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local LocalUIVisibilityGate = require(script.Parent.UI.LocalUIVisibilityGate)
local LocalGuiButtonState = require(script.Parent.UI.LocalGuiButtonState)

local StudioSaveResetController = {}

local GUI_NAME = "StudioSaveResetGui"
local started = false

local function createButton(parent: Instance, isTouchEnabled: boolean): TextButton
	local button = Instance.new("TextButton")
	button.Name = "ResetSaveButton"
	button.AnchorPoint = if isTouchEnabled then Vector2.new(0.5, 0) else Vector2.new(1, 0)
	-- 触屏时避开右侧怪兽面板；桌面仍保留右上角测试入口。
	button.Position = if isTouchEnabled
		then UDim2.new(0.5, 0, 0, 16)
		else UDim2.new(1, -20, 0, 80)
	button.Size = UDim2.fromOffset(210, 48)
	button.BackgroundColor3 = Color3.fromRGB(185, 45, 45)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.Text = "Delete Test Save"
	LocalGuiButtonState.SetEnabled(button, true)
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 150, 150)
	stroke.Thickness = 1
	stroke.Parent = button
	return button
end

function StudioSaveResetController.Start()
	if started or not RunService:IsStudio() then
		return
	end
	started = true

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local previous = playerGui:FindFirstChild(GUI_NAME)
	if previous then
		previous:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.Parent = playerGui
	LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Gameplay,
		function(visible)
			gui.Enabled = visible
		end,
		true
	)
	local button = createButton(gui, UserInputService.TouchEnabled)

	local remote = ReplicatedStorage
		:WaitForChild("Remotes")
		:WaitForChild(StudioSaveResetProtocol.RemoteName)
	assert(
		remote:IsA("RemoteFunction"),
		StudioSaveResetProtocol.RemoteName .. " 必须是 RemoteFunction"
	)

	local busy = false
	button.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		LocalGuiButtonState.SetEnabled(button, false)
		button.Text = "Deleting Test Save..."

		local invoked, result = pcall(remote.InvokeServer, remote)
		if invoked and result and result.Succeeded then
			button.Text = "Deleted. Please Play Again"
			button.BackgroundColor3 = Color3.fromRGB(55, 150, 75)
			return
		end

		local reason = if invoked and result then result.Reason else tostring(result)
		warn("Studio 测试删档失败：" .. tostring(reason))
		button.Text = "Delete Failed. Click to Retry"
		LocalGuiButtonState.SetEnabled(button, true)
		busy = false
	end)
end

return StudioSaveResetController
