--[[
	职责：在攻击选择期间显示并移动本地世界准星。
	输入：准星模板、旋转动画 ID、表面高度偏移；会话接收当前目标的合法领地。
	输出：可切换合法领地并停止的本地表现会话。
	内部算法：每帧把 GetMouseLocation 的 DeviceSafe viewport 坐标直接解析为世界点，复用 TerritoryPointRules 判定；合法时移动并显示 Clone。
	不负责：提交攻击、切换目标、相机、服务器校验、触摸输入或修改源模板。
]]

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WorldPointResolver = require(script.Parent.Parent.WorldPointResolver)
local AttackSelectionCoordinateDiagnostics = require(
	script.Parent.AttackSelectionCoordinateDiagnostics
)
local TerritoryPointRules = require(
	game:GetService("ReplicatedStorage").Shared.Monster.TerritoryPointRules
)

local LocalAttackCrosshairPresenter = {}

export type Territory = {
	CFrame: CFrame,
	Size: Vector3,
}

export type Options = {
	Template: Model,
	AnimationAssetId: number,
	SurfaceOffset: number,
	Diagnostics: AttackSelectionCoordinateDiagnostics.Session?,
}

export type Session = {
	SetTerritories: ({ Territory }) -> (),
	Stop: () -> (),
	IsActive: () -> boolean,
}

local function validOptions(options: Options): boolean
	return type(options) == "table"
		and typeof(options.Template) == "Instance"
		and options.Template:IsA("Model")
		and type(options.AnimationAssetId) == "number"
		and options.AnimationAssetId % 1 == 0
		and options.AnimationAssetId > 0
		and type(options.SurfaceOffset) == "number"
		and options.SurfaceOffset == options.SurfaceOffset
		and math.abs(options.SurfaceOffset) < math.huge
end

-- 输入：当前鼠标状态。
-- 输出：DeviceSafe viewport 坐标、左上 GUI inset 和已计入 CoreUI inset 的 screen 坐标。
local function getMouseCoordinates(): (Vector2, Vector2, Vector2)
	local rawMouseViewport = UserInputService:GetMouseLocation()
	local topLeftInset = GuiService:GetGuiInset()
	return rawMouseViewport, topLeftInset, rawMouseViewport - topLeftInset
end

local function project(camera: Camera?, worldPosition: Vector3?): Vector2?
	if not camera or not worldPosition then
		return nil
	end
	local viewportPoint = camera:WorldToViewportPoint(worldPosition)
	return Vector2.new(viewportPoint.X, viewportPoint.Y)
end

local function playAnimation(model: Model, animationAssetId: number): AnimationTrack?
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildWhichIsA("Animator")
	if not animator then
		warn("攻击准星缺少 Animator，旋转动画未播放")
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(animationAssetId)
	local succeeded, trackOrError = pcall(animator.LoadAnimation, animator, animation)
	animation:Destroy()
	if not succeeded then
		warn("攻击准星动画加载失败：" .. tostring(trackOrError))
		return nil
	end

	local track = trackOrError :: AnimationTrack
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action
	track:Play(0.1)
	return track
end

-- 输入：只读模板、正整数动画资源 ID、有限表面高度偏移。
-- 输出：独立本地准星会话；模板结构无效时返回 nil 和稳定原因。
function LocalAttackCrosshairPresenter.Start(
	options: Options
): (Session?, string?)
	if not validOptions(options) then
		return nil, "InvalidOptions"
	end

	local previousArchivable = options.Template.Archivable
	options.Template.Archivable = true
	local visual = options.Template:Clone()
	options.Template.Archivable = previousArchivable
	local root = visual:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		visual:Destroy()
		return nil, "RootPartUnavailable"
	end

	visual.Name = "_LocalAttackCrosshair"
	local parts = {}
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = descendant == root
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
			descendant.LocalTransparencyModifier = 1
			table.insert(parts, descendant)
		end
	end
	local humanoid = visual:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.AutoRotate = false
	end

	local baseRotation = visual:GetPivot().Rotation
	local visualAnchor = visual:FindFirstChild("Union", true)
	if visualAnchor and not visualAnchor:IsA("BasePart") then
		visualAnchor = nil
	end
	visual:PivotTo(CFrame.new(0, -10_000, 0) * baseRotation)
	visual.Parent = workspace
	local animationTrack = playAnimation(visual, options.AnimationAssetId)
	local territories: { Territory } = {}
	local visible = false
	local active = true
	local frame = 0
	local renderConnection: RBXScriptConnection? = nil
	if options.Diagnostics then
		options.Diagnostics.RecordCrosshair("Started", nil)
	end

	local function setVisible(nextVisible: boolean)
		if visible == nextVisible then
			return
		end
		visible = nextVisible
		for _, part in parts do
			if part.Parent then
				part.LocalTransparencyModifier = if nextVisible then 0 else 1
			end
		end
	end

	local function stop()
		if not active then
			return
		end
		active = false
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
		if animationTrack then
			animationTrack:Stop(0)
			animationTrack:Destroy()
			animationTrack = nil
		end
		visual:Destroy()
		if options.Diagnostics then
			options.Diagnostics.RecordCrosshair("Stopped", nil)
		end
	end

	renderConnection = RunService.RenderStepped:Connect(function()
		frame += 1
		local rawMouseViewport, guiInset, mouseScreen = getMouseCoordinates()
		local resolverViewport = rawMouseViewport
		local camera = workspace.CurrentCamera
		local point = nil
		local allowed = false
		local matchedTerritoryIndex = nil
		local reason = "Ready"
		if not active or not UserInputService.MouseEnabled or #territories == 0 then
			setVisible(false)
			reason = if not active
				then "Inactive"
				else if not UserInputService.MouseEnabled then "MouseDisabled" else "NoTerritory"
		else
			point = WorldPointResolver.Resolve(resolverViewport)
			if not point then
				setVisible(false)
				reason = "NoWorldPoint"
			else
				for territoryIndex, territory in territories do
					if TerritoryPointRules.Check(territory.CFrame, territory.Size, point).Allowed then
						allowed = true
						matchedTerritoryIndex = territoryIndex
						break
					end
				end
				if allowed then
					visual:PivotTo(
						CFrame.new(point + Vector3.new(0, options.SurfaceOffset, 0)) * baseRotation
					)
					setVisible(true)
					reason = "Allowed"
				else
					setVisible(false)
					reason = "OutsideTerritory"
				end
			end
		end

		if options.Diagnostics then
			local pivotWorld = if visible then visual:GetPivot().Position else nil
			local rootWorld = if visible and root.Parent then root.Position else nil
			local anchorWorld = if visible and visualAnchor then visualAnchor.Position else nil
			options.Diagnostics.RecordPreview({
				OccurredAt = os.clock(),
				ServerTime = workspace:GetServerTimeNow(),
				Frame = frame,
				Reason = reason,
				RawMouseViewport = rawMouseViewport,
				GuiInset = guiInset,
				MouseScreen = mouseScreen,
				ResolverViewport = resolverViewport,
				MouseIconEnabled = UserInputService.MouseIconEnabled,
				MouseBehavior = UserInputService.MouseBehavior,
				WorldPoint = point,
				Allowed = allowed,
				MatchedTerritoryIndex = matchedTerritoryIndex,
				Visible = visible,
				CameraCFrame = if camera then camera.CFrame else nil,
				CameraFieldOfView = if camera then camera.FieldOfView else nil,
				CameraViewportSize = if camera then camera.ViewportSize else nil,
				VisualPivotWorld = pivotWorld,
				VisualPivotViewport = project(camera, pivotWorld),
				VisualRootWorld = rootWorld,
				VisualRootViewport = project(camera, rootWorld),
				VisualAnchorWorld = anchorWorld,
				VisualAnchorViewport = project(camera, anchorWorld),
			})
		end
	end)

	return {
		SetTerritories = function(nextTerritories: { Territory })
			if not active then
				return
			end
			territories = table.clone(nextTerritories)
		end,
		Stop = stop,
		IsActive = function()
			return active
		end,
	}, nil
end

return LocalAttackCrosshairPresenter
