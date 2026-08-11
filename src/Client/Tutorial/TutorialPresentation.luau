--[[
	职责：用 ReplicatedStorage/TutorialAssets 中的 PopUp 与 Beam 模板显示客户端引导表现。
	输入：Create 接收 PlayerGui 和可选表现选项；Show 接收英文步骤定义和可选世界/UI 引导目标。
	输出：可 Show/Hide/Destroy 的表现句柄；支持完整教程模式和仅箭头/Beam 模式。
	内部算法：世界目标继续使用角色到目标的 Beam；UI/世界落点目标使用四块遮罩围出目标矩形，
	矩形和小手指每帧按当前 GUI 绝对位置或摄像机投影刷新。
	不负责：步骤判断、服务器查询、Plot/按钮定位、攻击输入或完成持久化。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ResponsiveUIScale = require(ReplicatedStorage.Shared.UI.ResponsiveUIScale)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local LocalUIVisibilityGate = require(
	script.Parent.Parent.UI.LocalUIVisibilityGate
)

local TutorialPresentation = {}

export type Definition = {
	Title: string,
	Info: string,
	TargetKind: string?,
}

export type WorldBounds = {
	CFrame: CFrame,
	Size: Vector3,
}

export type GuideTarget = {
	GuiObject: GuiObject?,
	WorldPart: BasePart?,
	WorldPosition: Vector3?,
	WorldBounds: WorldBounds?,
	ScreenCenter: boolean?,
}

export type Handle = {
	Show: (Definition, GuideTarget?) -> (),
	Hide: () -> (),
	Destroy: () -> (),
}

export type Options = {
	NamePrefix: string?,
	ShowPopup: boolean?,
	ShowClickMask: boolean?,
	ShowClickHand: boolean?,
}

local ORIGIN_ATTACHMENT_NAME = "TutorialGuideOrigin"
local TARGET_ATTACHMENT_NAME = "TutorialGuideTarget"
local MASK_TRANSPARENCY = 0.38
local TARGET_PADDING = 10
local MAX_WORLD_HIGHLIGHT_RATIO = 0.55
local WORLD_FOCUS_RATIO = 0.2
local RESPONSIVE_CONFIG = table.freeze({
	ReferenceViewport = Vector2.new(1280, 720),
	MinScale = 0.58,
	MaxScale = 1,
	TouchMinScale = 0.58,
})

local function childOfClass(parent: Instance?, name: string, className: string): Instance?
	local child = parent and parent:FindFirstChild(name)
	return if child and child:IsA(className) then child else nil
end

local function getCharacterRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isVisibleInHierarchy(instance: Instance?): boolean
	local current = instance
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
end

local function createOverlayGui(
	playerGui: PlayerGui,
	name: string,
	displayOrder: number
): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.Enabled = false
	gui.ResetOnSpawn = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension
	gui.ClipToDeviceSafeArea = true
	gui.AutoLocalize = false
	gui.Parent = playerGui
	return gui
end

local function createMaskFrame(parent: ScreenGui, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = MASK_TRANSPARENCY
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Selectable = false
	frame.ZIndex = 1
	frame.Parent = parent
	return frame
end

local function setFrameRect(frame: Frame, position: Vector2, size: Vector2)
	local width = math.max(0, size.X)
	local height = math.max(0, size.Y)
	frame.Position = UDim2.fromOffset(position.X, position.Y)
	frame.Size = UDim2.fromOffset(width, height)
	frame.Visible = width > 0 and height > 0
end

local function setMaskRect(
	frames: { Frame },
	highlight: Frame,
	viewport: Vector2,
	rectPosition: Vector2,
	rectSize: Vector2
)
	local left = math.clamp(rectPosition.X, 0, viewport.X)
	local top = math.clamp(rectPosition.Y, 0, viewport.Y)
	local right = math.clamp(rectPosition.X + rectSize.X, left, viewport.X)
	local bottom = math.clamp(rectPosition.Y + rectSize.Y, top, viewport.Y)
	local width = right - left
	local height = bottom - top

	setFrameRect(frames[1], Vector2.zero, Vector2.new(viewport.X, top))
	setFrameRect(
		frames[2],
		Vector2.new(0, bottom),
		Vector2.new(viewport.X, viewport.Y - bottom)
	)
	setFrameRect(frames[3], Vector2.new(0, top), Vector2.new(left, height))
	setFrameRect(
		frames[4],
		Vector2.new(right, top),
		Vector2.new(viewport.X - right, height)
	)

	highlight.Position = UDim2.fromOffset(left, top)
	highlight.Size = UDim2.fromOffset(width, height)
	highlight.Visible = width > 0 and height > 0
end

local function inflateRect(
	position: Vector2,
	size: Vector2,
	viewport: Vector2
): (Vector2, Vector2)
	local inflatedPosition = position - Vector2.new(TARGET_PADDING, TARGET_PADDING)
	local inflatedSize = size + Vector2.new(TARGET_PADDING * 2, TARGET_PADDING * 2)
	local left = math.clamp(inflatedPosition.X, 0, viewport.X)
	local top = math.clamp(inflatedPosition.Y, 0, viewport.Y)
	local right = math.clamp(inflatedPosition.X + inflatedSize.X, left, viewport.X)
	local bottom = math.clamp(inflatedPosition.Y + inflatedSize.Y, top, viewport.Y)
	return Vector2.new(left, top), Vector2.new(right - left, bottom - top)
end

local function projectWorldPoint(camera: Camera, worldPosition: Vector3): (Vector2?, number?)
	local projected, visible = camera:WorldToScreenPoint(worldPosition)
	if not visible or projected.Z <= 0 then
		return nil, projected.Z
	end
	return Vector2.new(projected.X, projected.Y), projected.Z
end

local function projectWorldBounds(
	camera: Camera,
	bounds: WorldBounds
): (Vector2?, Vector2?)
	local half = bounds.Size * 0.5
	local minimum: Vector2? = nil
	local maximum: Vector2? = nil
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local worldPoint = bounds.CFrame:PointToWorldSpace(
					Vector3.new(half.X * x, half.Y * y, half.Z * z)
				)
				local screenPoint = projectWorldPoint(camera, worldPoint)
				if screenPoint then
					minimum = if minimum
						then Vector2.new(
							math.min(minimum.X, screenPoint.X),
							math.min(minimum.Y, screenPoint.Y)
						)
						else screenPoint
					maximum = if maximum
						then Vector2.new(
							math.max(maximum.X, screenPoint.X),
							math.max(maximum.Y, screenPoint.Y)
						)
						else screenPoint
				end
			end
		end
	end
	if not minimum or not maximum then
		return nil, nil
	end
	return minimum, maximum - minimum
end

local function resolveGuiRect(target: GuiObject): (Vector2?, Vector2?)
	if not target.Parent or not isVisibleInHierarchy(target) then
		return nil, nil
	end
	return target.AbsolutePosition, target.AbsoluteSize
end

local function resolveGuideTemplate(playerGui: PlayerGui): GuiObject?
	local hud = playerGui:FindFirstChild("HUD")
	local guide = hud and hud:FindFirstChild("Guide")
	return if guide and guide:IsA("GuiObject") then guide else nil
end

function TutorialPresentation.Create(
	playerGui: PlayerGui,
	options: Options?
): (Handle?, string?)
	assert(playerGui:IsA("PlayerGui"), "playerGui 必须是 PlayerGui")
	local namePrefix = if options and options.NamePrefix
		then options.NamePrefix
		else "Tutorial"
	assert(type(namePrefix) == "string" and namePrefix ~= "", "NamePrefix 无效")
	local showPopup = if options and options.ShowPopup ~= nil
		then options.ShowPopup
		else true
	local showClickMask = if options and options.ShowClickMask ~= nil
		then options.ShowClickMask
		else true
	local showClickHand = if options and options.ShowClickHand ~= nil
		then options.ShowClickHand
		else true
	local guiName = namePrefix .. "PopUp"
	local clickMaskGuiName = namePrefix .. "ClickMask"
	local clickHandGuiName = namePrefix .. "ClickHand"
	local assets = ReplicatedStorage:WaitForChild("TutorialAssets", 20)
	if not assets or not assets:IsA("Folder") then
		return nil, "TutorialAssetsUnavailable"
	end
	local popupTemplate = childOfClass(assets, "PopUp", "ScreenGui")
	local beamTemplate = childOfClass(assets, "Beam", "Beam")
	if not popupTemplate or not beamTemplate then
		return nil, "InvalidTutorialAssets"
	end

	local previous = playerGui:FindFirstChild(guiName)
	if previous then
		previous:Destroy()
	end
	for _, name in { clickMaskGuiName, clickHandGuiName } do
		local oldOverlay = playerGui:FindFirstChild(name)
		if oldOverlay then
			oldOverlay:Destroy()
		end
	end

	local gui: ScreenGui? = nil
	local title: TextLabel? = nil
	local info: TextLabel? = nil
	local uiScale: UIScale? = nil
	if showPopup then
		local popup = popupTemplate:Clone() :: ScreenGui
		popup.Name = guiName
		popup.Enabled = false
		popup.ResetOnSpawn = false
		popup.DisplayOrder = math.max(popup.DisplayOrder, 200)
		popup.AutoLocalize = false
		local tip = childOfClass(popup, "Tip", "Frame")
		local titleFrame = childOfClass(tip, "Title", "Frame")
		title = childOfClass(titleFrame, "Title", "TextLabel") :: TextLabel?
		info = childOfClass(tip, "Info", "TextLabel") :: TextLabel?
		uiScale = popup:FindFirstChildOfClass("UIScale")
		if not tip or not title or not info or not uiScale then
			popup:Destroy()
			return nil, "InvalidTutorialPopupHierarchy"
		end
		title.AutoLocalize = false
		info.AutoLocalize = false
		info.RichText = true
		info.TextScaled = true
		popup.Parent = playerGui
		gui = popup
	end

	local clickMaskGui = createOverlayGui(playerGui, clickMaskGuiName, 190)
	local clickHandGui = createOverlayGui(playerGui, clickHandGuiName, 210)
	local overlayCoordinateSpace = Instance.new("Frame")
	overlayCoordinateSpace.Name = "CoordinateSpace"
	overlayCoordinateSpace.BackgroundTransparency = 1
	overlayCoordinateSpace.BorderSizePixel = 0
	overlayCoordinateSpace.Position = UDim2.fromOffset(0, 0)
	overlayCoordinateSpace.Size = UDim2.fromScale(1, 1)
	overlayCoordinateSpace.Active = false
	overlayCoordinateSpace.Selectable = false
	overlayCoordinateSpace.ZIndex = 0
	overlayCoordinateSpace.Parent = clickHandGui
	local maskFrames = {
		createMaskFrame(clickMaskGui, "Top"),
		createMaskFrame(clickMaskGui, "Bottom"),
		createMaskFrame(clickMaskGui, "Left"),
		createMaskFrame(clickMaskGui, "Right"),
	}
	local highlight = Instance.new("Frame")
	highlight.Name = "TargetHighlight"
	highlight.BackgroundTransparency = 1
	highlight.BorderColor3 = Color3.fromRGB(255, 232, 76)
	highlight.BorderSizePixel = 3
	highlight.Active = false
	highlight.Selectable = false
	highlight.ZIndex = 2
	highlight.Visible = false
	highlight.Parent = clickMaskGui

	local guideTemplate = resolveGuideTemplate(playerGui)
	local guide: GuiObject? = nil
	if guideTemplate then
		guideTemplate.Visible = false
		guide = guideTemplate:Clone()
		guide.Name = "Guide"
		guide.AnchorPoint = Vector2.new(0.5, 0.5)
		guide.BackgroundTransparency = 1
		guide.Active = false
		guide.Selectable = false
		guide.ZIndex = 1
		guide.Visible = false
		guide.Parent = clickHandGui
	end

	local visibilityGate
	local beam: Beam? = nil
	local originAttachment: Attachment? = nil
	local targetAttachment: Attachment? = nil
	local currentTarget: BasePart? = nil
	local currentGuideTarget: GuideTarget? = nil
	local clickGuideRequested = false
	local presentationVisible = false
	local connections: { RBXScriptConnection } = {}
	local cameraConnection: RBXScriptConnection? = nil
	local renderConnection: RBXScriptConnection? = nil
	local destroyed = false
	local handTime = 0

	local function updateScale()
		local camera = Workspace.CurrentCamera
		if uiScale and camera and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0 then
			uiScale.Scale = ResponsiveUIScale.Compute(
				camera.ViewportSize,
				UserInputService.TouchEnabled,
				RESPONSIVE_CONFIG
			)
		end
	end

	local function bindCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = Workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end

	local function clearBeam()
		currentTarget = nil
		if beam then
			beam:Destroy()
			beam = nil
		end
		if originAttachment then
			originAttachment:Destroy()
			originAttachment = nil
		end
		if targetAttachment then
			targetAttachment:Destroy()
			targetAttachment = nil
		end
	end

	local function setTarget(target: BasePart?)
		local root = getCharacterRoot()
		if target == currentTarget
			and target ~= nil
			and target.Parent ~= nil
			and root ~= nil
			and originAttachment ~= nil
			and originAttachment.Parent == root
			and targetAttachment ~= nil
			and targetAttachment.Parent == target
		then
			return
		end
		clearBeam()
		if not target or not target.Parent or not root then
			return
		end

		currentTarget = target
		originAttachment = Instance.new("Attachment")
		originAttachment.Name = ORIGIN_ATTACHMENT_NAME
		originAttachment.Position = Vector3.new(0, -2, 0)
		originAttachment.Parent = root
		targetAttachment = Instance.new("Attachment")
		targetAttachment.Name = TARGET_ATTACHMENT_NAME
		targetAttachment.Position = Vector3.new(0, target.Size.Y * 0.5 + 0.5, 0)
		targetAttachment.Parent = target
		beam = beamTemplate:Clone() :: Beam
		beam.Attachment0 = originAttachment
		beam.Attachment1 = targetAttachment
		beam.Enabled = true
		beam.Parent = originAttachment
	end

	local function setClickGuideVisible(visible: boolean)
		presentationVisible = visible
		clickMaskGui.Enabled = showClickMask and visible and clickGuideRequested
		clickHandGui.Enabled = showClickHand and visible and clickGuideRequested
	end

	local function updateHandSize(viewport: Vector2): Vector2
		if not guide then
			return Vector2.zero
		end
		local sourceSize = if guideTemplate then guideTemplate.AbsoluteSize else Vector2.zero
		local fallback = math.clamp(math.min(viewport.X, viewport.Y) * 0.12, 48, 110)
		local width = if sourceSize.X > 0 then math.clamp(sourceSize.X, 48, 140) else fallback
		local height = if sourceSize.Y > 0 then math.clamp(sourceSize.Y, 48, 110) else fallback
		guide.Size = UDim2.fromOffset(width, height)
		return Vector2.new(width, height)
	end

	local function resolveCurrentRect(): (Vector2?, Vector2?, Vector2?)
		local target = currentGuideTarget
		local camera = Workspace.CurrentCamera
		local overlayOrigin = overlayCoordinateSpace.AbsolutePosition
		local viewport = overlayCoordinateSpace.AbsoluteSize
		if not target or not camera or viewport.X <= 0 or viewport.Y <= 0 then
			return nil, nil, nil
		end

		if target.GuiObject then
			local position, size = resolveGuiRect(target.GuiObject)
			if position and size and size.X > 0 and size.Y > 0 then
				local rectPosition, rectSize = inflateRect(
					position - overlayOrigin,
					size,
					viewport
				)
				return rectPosition, rectSize, viewport
			end
		end

		if target.WorldBounds then
			local position, size = projectWorldBounds(camera, target.WorldBounds)
			if position and size then
				position -= overlayOrigin
				if size.X > viewport.X * MAX_WORLD_HIGHLIGHT_RATIO
					or size.Y > viewport.Y * MAX_WORLD_HIGHLIGHT_RATIO
				then
					local center = position + size * 0.5
					local side = math.clamp(
						math.min(viewport.X, viewport.Y) * WORLD_FOCUS_RATIO,
						110,
						260
					)
					position = center - Vector2.new(side * 0.5, side * 0.5)
					size = Vector2.new(side, side)
				end
				local rectPosition, rectSize = inflateRect(position, size, viewport)
				return rectPosition, rectSize, viewport
			end
		end

		if target.WorldPosition then
			local position = projectWorldPoint(camera, target.WorldPosition)
			if position then
				position -= overlayOrigin
				local side = math.clamp(math.min(viewport.X, viewport.Y) * 0.2, 110, 260)
				local rectPosition, rectSize = inflateRect(
					position - Vector2.new(side * 0.5, side * 0.5),
					Vector2.new(side, side),
					viewport
				)
				return rectPosition, rectSize, viewport
			end
		end

		if target.ScreenCenter then
			local side = math.clamp(
				math.min(viewport.X, viewport.Y) * WORLD_FOCUS_RATIO,
				110,
				260
			)
			local rectPosition, rectSize = inflateRect(
				Vector2.new(viewport.X * 0.5 - side * 0.5, viewport.Y * 0.5 - side * 0.5),
				Vector2.new(side, side),
				viewport
			)
			return rectPosition, rectSize, viewport
		end

		return nil, nil, nil
	end

	local function updateClickGuide(deltaTime: number)
		handTime += deltaTime
		if not presentationVisible or not clickGuideRequested then
			clickMaskGui.Enabled = false
			clickHandGui.Enabled = false
			highlight.Visible = false
			if guide then
				guide.Visible = false
			end
			return
		end
		local rectPosition, rectSize, viewport = resolveCurrentRect()
		if not rectPosition or not rectSize or not viewport then
			clickMaskGui.Enabled = false
			clickHandGui.Enabled = false
			highlight.Visible = false
			if guide then
				guide.Visible = false
			end
			return
		end

		clickMaskGui.Enabled = showClickMask
		clickHandGui.Enabled = showClickHand
		if showClickMask then
			setMaskRect(maskFrames, highlight, viewport, rectPosition, rectSize)
		else
			highlight.Visible = false
		end
		if showClickHand and guide then
			local guideSize = updateHandSize(viewport)
			local targetPoint = rectPosition + rectSize * 0.5
			local bob = math.sin(handTime * 5) * 5
			local position = targetPoint + Vector2.new(guideSize.X * 0.18, guideSize.Y * 0.45 + bob)
			local half = guideSize * 0.5
			position = Vector2.new(
				math.clamp(position.X, half.X, math.max(half.X, viewport.X - half.X)),
				math.clamp(position.Y, half.Y, math.max(half.Y, viewport.Y - half.Y))
			)
			guide.Position = UDim2.fromOffset(position.X, position.Y)
			guide.Visible = true
		end
	end

	bindCamera()
	table.insert(connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
	renderConnection = RunService.RenderStepped:Connect(updateClickGuide)
	visibilityGate = LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Tutorial,
		function(visible)
			if gui then
				gui.Enabled = visible
			end
			setClickGuideVisible(visible)
		end,
		false
	)

	local handle = {} :: any
	function handle.Show(definition: Definition, target: GuideTarget?)
		if destroyed then
			return
		end
		if title and info then
			title.Text = "TIP:"
			info.Text = string.format("<b>%s</b>\n%s", definition.Title, definition.Info)
		end
		currentGuideTarget = target
		clickGuideRequested = target ~= nil
		setTarget(if target then target.WorldPart else nil)
		visibilityGate:SetDesiredVisible(true)
	end

	function handle.Hide()
		if destroyed then
			return
		end
		visibilityGate:SetDesiredVisible(false)
		currentGuideTarget = nil
		clickGuideRequested = false
		clearBeam()
	end

	function handle.Destroy()
		if destroyed then
			return
		end
		destroyed = true
		currentGuideTarget = nil
		clickGuideRequested = false
		clearBeam()
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		if visibilityGate then
			visibilityGate:Destroy()
			visibilityGate = nil
		end
		if guideTemplate and guideTemplate.Parent then
			guideTemplate.Visible = false
		end
		if clickMaskGui.Parent then
			clickMaskGui:Destroy()
		end
		if clickHandGui.Parent then
			clickHandGui:Destroy()
		end
		if gui and gui.Parent then
			gui:Destroy()
		end
	end

	return handle, nil
end

return TutorialPresentation
