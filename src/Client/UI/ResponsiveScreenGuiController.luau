--[[
	职责：统一更新带有响应式配置的 ScreenGui 根 UIScale。
	输入：PlayerGui 中 UIScale 的 Studio 属性，以及 CurrentCamera.ViewportSize。
	输出：当视口尺寸变化时，把 UIScale.Scale 更新为基准缩放乘以视口比例。
	内部算法：取当前视口相对于配置参考视口的宽高较小比例；只有在 UIScale
	或 ScreenGui 上配置了参考视口时才接管该 UIScale，不按电脑/手机写分支。
	不负责：修改 UI 的 AnchorPoint、Position、Size、Safe Area 或世界空间 BillboardGui。

	Studio 配置：
	- ResponsiveReferenceViewport (Vector2，必填)：制作该 UI 时使用的参考视口。
	- ResponsiveBaseScale (number，可选)：覆盖运行开始时 UIScale.Scale 的基准值。
	- ResponsiveMinScale / ResponsiveMaxScale (number，可选)：该 UI 的缩放边界。
	这些属性优先读取 UIScale，其次读取所属 ScreenGui。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ResponsiveUIScale = require(
	ReplicatedStorage.Shared.UI.ResponsiveUIScale
)

local ResponsiveScreenGuiController = {}

local REFERENCE_VIEWPORT_ATTRIBUTE = "ResponsiveReferenceViewport"
local BASE_SCALE_ATTRIBUTE = "ResponsiveBaseScale"
local MIN_SCALE_ATTRIBUTE = "ResponsiveMinScale"
local MAX_SCALE_ATTRIBUTE = "ResponsiveMaxScale"

type Binding = {
	ScreenGui: ScreenGui,
	UIScale: UIScale,
	ReferenceViewport: Vector2,
	BaseScale: number,
	MinScale: number?,
	MaxScale: number?,
}

local bindings: {[ScreenGui]: Binding} = {}
local started = false
local playerGui: PlayerGui?
local cameraConnection: RBXScriptConnection?
local playerGuiChildAddedConnection: RBXScriptConnection?

local function readAttribute(
	screenGui: ScreenGui,
	uiScale: UIScale,
	attributeName: string
): any
	local value = uiScale:GetAttribute(attributeName)
	if value ~= nil then
		return value
	end
	return screenGui:GetAttribute(attributeName)
end

local function readReferenceViewport(
	screenGui: ScreenGui,
	uiScale: UIScale
): Vector2?
	local value = readAttribute(
		screenGui,
		uiScale,
		REFERENCE_VIEWPORT_ATTRIBUTE
	)
	if value == nil then
		return nil
	end
	if typeof(value) ~= "Vector2" or value.X <= 0 or value.Y <= 0 then
		warn(
			("[ResponsiveScreenGuiController] %s.%s 的 %s 必须是大于 0 的 Vector2")
				:format(screenGui:GetFullName(), uiScale.Name, REFERENCE_VIEWPORT_ATTRIBUTE)
		)
		return nil
	end
	return value
end

local function readOptionalScale(
	screenGui: ScreenGui,
	uiScale: UIScale,
	attributeName: string
): number?
	local value = readAttribute(screenGui, uiScale, attributeName)
	if value == nil then
		return nil
	end
	if type(value) ~= "number" or value <= 0 or value ~= value or value == math.huge then
		warn(
			("[ResponsiveScreenGuiController] %s.%s 的 %s 必须是大于 0 的数字")
				:format(screenGui:GetFullName(), uiScale.Name, attributeName)
		)
		return nil
	end
	return value
end

local function bind(screenGui: ScreenGui)
	local uiScale = screenGui:FindFirstChildOfClass("UIScale")
	if not uiScale then
		return
	end

	local referenceViewport = readReferenceViewport(screenGui, uiScale)
	if not referenceViewport then
		return
	end

	local baseScale = readOptionalScale(
		screenGui,
		uiScale,
		BASE_SCALE_ATTRIBUTE
	) or uiScale.Scale
	if baseScale <= 0 then
		warn(
			("[ResponsiveScreenGuiController] %s.%s 的初始 Scale 必须大于 0")
				:format(screenGui:GetFullName(), uiScale.Name)
		)
		return
	end

	local minScale = readOptionalScale(screenGui, uiScale, MIN_SCALE_ATTRIBUTE)
	local maxScale = readOptionalScale(screenGui, uiScale, MAX_SCALE_ATTRIBUTE)
	if minScale and maxScale and maxScale < minScale then
		warn(
			("[ResponsiveScreenGuiController] %s.%s 的 ResponsiveMaxScale 不能小于 ResponsiveMinScale")
				:format(screenGui:GetFullName(), uiScale.Name)
		)
		return
	end

	bindings[screenGui] = {
		ScreenGui = screenGui,
		UIScale = uiScale,
		ReferenceViewport = referenceViewport,
		BaseScale = baseScale,
		MinScale = minScale,
		MaxScale = maxScale,
	}
end

local function apply(binding: Binding, viewportSize: Vector2)
	local ratio = ResponsiveUIScale.ComputeRatio(
		viewportSize,
		binding.ReferenceViewport
	)
	if binding.MinScale then
		ratio = math.max(ratio, binding.MinScale)
	end
	if binding.MaxScale then
		ratio = math.min(ratio, binding.MaxScale)
	end
	binding.UIScale.Scale = binding.BaseScale * ratio
end

local function updateAll()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return
	end

	for screenGui, binding in pairs(bindings) do
		if screenGui.Parent == nil or binding.UIScale.Parent ~= screenGui then
			bindings[screenGui] = nil
		else
			apply(binding, viewportSize)
		end
	end
end

local function bindCamera(camera: Camera?)
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateAll)
	end
	updateAll()
end

function ResponsiveScreenGuiController.Start()
	if started then
		return
	end
	started = true

	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") then
			bind(child)
		end
	end

	playerGuiChildAddedConnection = playerGui.ChildAdded:Connect(function(child)
		if child:IsA("ScreenGui") then
			bind(child)
			updateAll()
		end
	end)

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(Workspace.CurrentCamera)
	end)
	bindCamera(Workspace.CurrentCamera)
end

return table.freeze(ResponsiveScreenGuiController)
