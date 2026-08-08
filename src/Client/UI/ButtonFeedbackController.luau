--[[
	职责：为本地玩家可见的所有 GuiButton 提供统一的悬停与点击缩放反馈。
	输入：PlayerGui/Workspace 中新增或已有的 GuiButton，以及鼠标悬停、按钮激活事件。
	输出：悬停时放大；点击或触摸激活时短暂放大，再恢复到当前悬停或基础倍率。
	内部算法：每个按钮只创建一个独立 UIScale；MouseEnter/Leave 驱动悬停目标，
	Activated 驱动点击脉冲；新的动画会取消旧动画，避免快速连续点击叠加缩放。
	不负责：按钮业务、按钮可见性、布局、文字、颜色、声音或世界按钮的点击判定。
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ButtonFeedbackController = {}

local FEEDBACK_SCALE_NAME = "InteractionFeedbackScale"
local HOVER_MULTIPLIER = 1.08
local PRESS_MULTIPLIER = 1.15
local PRESS_HOLD_SECONDS = 0.08

local HOVER_TWEEN_INFO = TweenInfo.new(
	0.12,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out
)
local PRESS_TWEEN_INFO = TweenInfo.new(
	0.08,
	Enum.EasingStyle.Back,
	Enum.EasingDirection.Out
)
local RELEASE_TWEEN_INFO = TweenInfo.new(
	0.1,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out
)

type Binding = {
	Button: GuiButton,
	Scale: UIScale,
	BaseScale: number,
	Hovered: boolean,
	Generation: number,
	Tween: Tween?,
	Connections: {RBXScriptConnection},
}

local bindings: {[GuiButton]: Binding} = {}
local started = false

local function cancelTween(binding: Binding)
	local tween = binding.Tween
	if tween then
		tween:Cancel()
		binding.Tween = nil
	end
end

local function playScale(
	binding: Binding,
	multiplier: number,
	tweenInfo: TweenInfo
)
	cancelTween(binding)
	local tween = TweenService:Create(binding.Scale, tweenInfo, {
		Scale = binding.BaseScale * multiplier,
	})
	binding.Tween = tween
	tween.Completed:Connect(function()
		if binding.Tween == tween then
			binding.Tween = nil
		end
	end)
	tween:Play()
end

local function restoreTarget(binding: Binding)
	playScale(
		binding,
		if binding.Hovered then HOVER_MULTIPLIER else 1,
		RELEASE_TWEEN_INFO
	)
end

local function unbind(button: GuiButton)
	local binding = bindings[button]
	if not binding then
		return
	end

	for _, connection in binding.Connections do
		connection:Disconnect()
	end
	cancelTween(binding)
	bindings[button] = nil
end

local function bind(button: GuiButton)
	if bindings[button] then
		return
	end

	local existingScale = button:FindFirstChild(FEEDBACK_SCALE_NAME)
	if existingScale and not existingScale:IsA("UIScale") then
		warn(
			("[ButtonFeedbackController] %s 已存在非 UIScale 的 %s")
				:format(button:GetFullName(), FEEDBACK_SCALE_NAME)
		)
		return
	end

	local scale = existingScale :: UIScale?
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = FEEDBACK_SCALE_NAME
		scale.Scale = 1
		scale.Parent = button
	end
	if scale.Scale <= 0 or scale.Scale ~= scale.Scale or scale.Scale == math.huge then
		scale.Scale = 1
	end

	local binding: Binding = {
		Button = button,
		Scale = scale,
		BaseScale = scale.Scale,
		Hovered = false,
		Generation = 0,
		Tween = nil,
		Connections = {},
	}
	bindings[button] = binding

	table.insert(binding.Connections, button.MouseEnter:Connect(function()
		binding.Hovered = true
		binding.Generation += 1
		playScale(binding, HOVER_MULTIPLIER, HOVER_TWEEN_INFO)
	end))
	table.insert(binding.Connections, button.MouseLeave:Connect(function()
		binding.Hovered = false
		binding.Generation += 1
		restoreTarget(binding)
	end))
	table.insert(binding.Connections, button.Activated:Connect(function()
		binding.Generation += 1
		local generation = binding.Generation
		playScale(binding, PRESS_MULTIPLIER, PRESS_TWEEN_INFO)
		task.delay(PRESS_HOLD_SECONDS, function()
			if binding.Generation == generation and button.Parent then
				restoreTarget(binding)
			end
		end)
	end))
	table.insert(binding.Connections, button.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unbind(button)
		end
	end))
end

local function scan(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") then
			bind(descendant)
		end
	end
end

function ButtonFeedbackController.Start()
	if started then
		return
	end
	started = true

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	scan(playerGui)
	scan(Workspace)

	playerGui.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiButton") then
			bind(descendant)
		end
	end)
	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiButton") then
			bind(descendant)
		end
	end)
end

return table.freeze(ButtonFeedbackController)
