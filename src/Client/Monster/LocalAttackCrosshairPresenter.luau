--[[
	职责：在攻击选择期间显示并移动本地世界准星。
	输入：准星模板、旋转动画 ID、表面高度偏移；会话接收当前目标的合法领地。
	输出：可切换合法领地并停止的本地表现会话。
	内部算法：每帧解析鼠标世界命中点，复用 TerritoryPointRules 判定；合法时移动并显示 Clone。
	不负责：提交攻击、切换目标、相机、服务器校验、触摸输入或修改源模板。
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WorldPointResolver = require(script.Parent.Parent.WorldPointResolver)
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

local function isAllowed(territories: { Territory }, point: Vector3): boolean
	for _, territory in territories do
		if TerritoryPointRules.Check(territory.CFrame, territory.Size, point).Allowed then
			return true
		end
	end
	return false
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
	visual:PivotTo(CFrame.new(0, -10_000, 0) * baseRotation)
	visual.Parent = workspace
	local animationTrack = playAnimation(visual, options.AnimationAssetId)
	local territories: { Territory } = {}
	local visible = false
	local active = true
	local renderConnection: RBXScriptConnection? = nil

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
	end

	renderConnection = RunService.RenderStepped:Connect(function()
		if not active or not UserInputService.MouseEnabled or #territories == 0 then
			setVisible(false)
			return
		end
		local point = WorldPointResolver.Resolve(UserInputService:GetMouseLocation())
		if not point or not isAllowed(territories, point) then
			setVisible(false)
			return
		end

		visual:PivotTo(
			CFrame.new(point + Vector3.new(0, options.SurfaceOffset, 0)) * baseRotation
		)
		setVisible(true)
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
