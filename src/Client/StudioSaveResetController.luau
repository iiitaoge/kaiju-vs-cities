--[[
	职责：在 Studio Play 中创建一键删除当前测试玩家存档的 UI。
	输入：Start 无参数；玩家点击按钮。
	输出：按钮展示处理中/成功/失败；成功后服务器退出当前玩家。
	内部算法：Studio 门禁 → 创建单按钮 ScreenGui → 调用 StudioSaveReset RemoteFunction。
	不负责：选择 UserId、DataStore、保存会话或正式服 UI。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StudioSaveResetProtocol = require(
	ReplicatedStorage.Shared.Persistence.StudioSaveResetProtocol
)

local StudioSaveResetController = {}

local GUI_NAME = "StudioSaveResetGui"
local started = false

local function createButton(parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Name = "ResetSaveButton"
	button.AnchorPoint = Vector2.new(1, 0)
	-- 避开 Roblox 顶部 CoreGui，保证 Studio 鼠标输入命中测试按钮。
	button.Position = UDim2.new(1, -20, 0, 80)
	button.Size = UDim2.fromOffset(210, 48)
	button.BackgroundColor3 = Color3.fromRGB(185, 45, 45)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.Text = "一键删除测试存档"
	button.AutoButtonColor = true
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
	local button = createButton(gui)

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
		button.Interactable = false
		button.Text = "正在删除测试存档..."

		local invoked, result = pcall(remote.InvokeServer, remote)
		if invoked and result and result.Succeeded then
			button.Text = "已删除，请重新 Play"
			button.BackgroundColor3 = Color3.fromRGB(55, 150, 75)
			return
		end

		local reason = if invoked and result then result.Reason else tostring(result)
		warn("Studio 测试删档失败：" .. tostring(reason))
		button.Text = "删除失败，点击重试"
		button.Interactable = true
		busy = false
	end)
end

return StudioSaveResetController
