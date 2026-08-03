local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ValueValidation = require(ReplicatedStorage.Shared.ValueValidation)

local visualRemote = ReplicatedStorage
	:WaitForChild("Remotes")
	:WaitForChild("ModelMovementVisual")
assert(visualRemote:IsA("RemoteEvent"), "ModelMovementVisual 必须是 RemoteEvent")

type VisualCommand = {
	Model: Model,
	RequestId: number,
	StartCFrame: CFrame,
	TargetCFrame: CFrame,
	StartedAt: number,
	Duration: number,
	EasingStyle: Enum.EasingStyle,
	EasingDirection: Enum.EasingDirection,
}

type VisualRecord = {
	VisualModel: Model,
	PrimaryPart: BasePart,
	PivotToPrimary: CFrame,
	ActiveRequestId: number,
	ActiveTween: Tween?,
	SourceTransparency: { [BasePart]: number },
	MirroredTracks: { [AnimationTrack]: AnimationTrack },
	TrackConnections: { [AnimationTrack]: RBXScriptConnection },
	AnimationConnection: RBXScriptConnection?,
	AncestryConnection: RBXScriptConnection?,
}

export type PresentResult = {
	Accepted: boolean,
	Reason: string?,
}

local recordsBySource: { [Model]: VisualRecord } = setmetatable({}, { __mode = "k" })

local visualsRoot = Instance.new("Folder")
visualsRoot.Name = "_LocalModelMovementVisuals"
visualsRoot.Parent = workspace

local function validateCommand(value): VisualCommand?
	if type(value) ~= "table" then
		return nil
	end
	if typeof(value.Model) ~= "Instance" or not value.Model:IsA("Model") then
		return nil
	end
	if not ValueValidation.IsFiniteNumber(value.RequestId) or value.RequestId < 1 then
		return nil
	end
	if typeof(value.StartCFrame) ~= "CFrame"
		or typeof(value.TargetCFrame) ~= "CFrame" then
		return nil
	end
	if not ValueValidation.IsFiniteNumber(value.StartedAt) then
		return nil
	end
	if not ValueValidation.IsFiniteNumber(value.Duration) or value.Duration <= 0 then
		return nil
	end
	if typeof(value.EasingStyle) ~= "EnumItem"
		or value.EasingStyle.EnumType ~= Enum.EasingStyle then
		return nil
	end
	if typeof(value.EasingDirection) ~= "EnumItem"
		or value.EasingDirection.EnumType ~= Enum.EasingDirection then
		return nil
	end

	return value :: VisualCommand
end

local function cleanupRecord(source: Model, record: VisualRecord)
	if recordsBySource[source] ~= record then
		return
	end
	recordsBySource[source] = nil

	if record.ActiveTween then
		local activeTween = record.ActiveTween
		record.ActiveTween = nil
		activeTween:Cancel()
		activeTween:Destroy()
	end
	if record.AnimationConnection then
		record.AnimationConnection:Disconnect()
	end
	if record.AncestryConnection then
		record.AncestryConnection:Disconnect()
	end
	for sourceTrack, connection in record.TrackConnections do
		connection:Disconnect()
		local visualTrack = record.MirroredTracks[sourceTrack]
		if visualTrack then
			visualTrack:Stop(0)
			visualTrack:Destroy()
		end
	end
	for part, transparency in record.SourceTransparency do
		if part.Parent then
			part.LocalTransparencyModifier = transparency
		end
	end
	if record.VisualModel.Parent then
		record.VisualModel:Destroy()
	end
end

local function mirrorTrack(record: VisualRecord, sourceTrack: AnimationTrack)
	if record.MirroredTracks[sourceTrack] or not sourceTrack.IsPlaying then
		return
	end

	local visualAnimator = record.VisualModel:FindFirstChildWhichIsA("Animator", true)
	local animation = sourceTrack.Animation
	if not visualAnimator or not animation or animation.AnimationId == "" then
		return
	end

	local visualAnimation = Instance.new("Animation")
	visualAnimation.AnimationId = animation.AnimationId
	local succeeded, visualTrack = pcall(
		visualAnimator.LoadAnimation,
		visualAnimator,
		visualAnimation
	)
	visualAnimation:Destroy()
	if not succeeded then
		warn("本地视觉动画加载失败：", visualTrack)
		return
	end

	visualTrack.Looped = sourceTrack.Looped
	visualTrack.Priority = sourceTrack.Priority
	local weight = math.max(sourceTrack.WeightTarget, 0.001)
	visualTrack:Play(0, weight, sourceTrack.Speed)
	record.MirroredTracks[sourceTrack] = visualTrack

	task.defer(function()
		if record.MirroredTracks[sourceTrack] == visualTrack
			and sourceTrack.IsPlaying
			and visualTrack.IsPlaying then
			visualTrack.TimePosition = sourceTrack.TimePosition
		end
	end)

	local connection
	connection = sourceTrack.Stopped:Connect(function()
		if record.MirroredTracks[sourceTrack] ~= visualTrack then
			return
		end
		record.MirroredTracks[sourceTrack] = nil
		record.TrackConnections[sourceTrack] = nil
		connection:Disconnect()
		visualTrack:Stop(0.05)
		task.delay(0.05, function()
			visualTrack:Destroy()
		end)
	end)
	record.TrackConnections[sourceTrack] = connection
end

local function createRecord(source: Model): VisualRecord?
	if not source:IsDescendantOf(workspace) then
		return nil
	end

	local previousArchivable = source.Archivable
	source.Archivable = true
	local visualModel = source:Clone()
	source.Archivable = previousArchivable
	local primaryPart = visualModel.PrimaryPart
	if not primaryPart then
		visualModel:Destroy()
		return nil
	end

	visualModel.Name = source.Name .. "_LocalVisual"
	for _, descendant in visualModel:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.LocalTransparencyModifier = 0
		end
	end
	visualModel:PivotTo(source:GetPivot())
	visualModel.Parent = visualsRoot

	local sourceTransparency = {}
	for _, descendant in source:GetDescendants() do
		if descendant:IsA("BasePart") then
			sourceTransparency[descendant] = descendant.LocalTransparencyModifier
			descendant.LocalTransparencyModifier = 1
		end
	end

	local record: VisualRecord = {
		VisualModel = visualModel,
		PrimaryPart = primaryPart,
		PivotToPrimary = visualModel:GetPivot():ToObjectSpace(primaryPart.CFrame),
		ActiveRequestId = 0,
		ActiveTween = nil,
		SourceTransparency = sourceTransparency,
		MirroredTracks = {},
		TrackConnections = {},
		AnimationConnection = nil,
		AncestryConnection = nil,
	}
	recordsBySource[source] = record

	local sourceAnimator = source:FindFirstChildWhichIsA("Animator", true)
	if sourceAnimator then
		record.AnimationConnection = sourceAnimator.AnimationPlayed:Connect(function(track)
			mirrorTrack(record, track)
		end)
		for _, track in sourceAnimator:GetPlayingAnimationTracks() do
			mirrorTrack(record, track)
		end
	end

	record.AncestryConnection = source.AncestryChanged:Connect(function()
		if not source:IsDescendantOf(workspace) then
			cleanupRecord(source, record)
		end
	end)
	return record
end

-- 输入：
--   command.Model：服务器权威模型。
--   command.RequestId：该模型单调递增的视觉移动编号。
--   command.StartCFrame/TargetCFrame：服务器权威起点与终点。
--   command.StartedAt/Duration：同步服务器时间和持续时间。
--   command.EasingStyle/EasingDirection：服务器使用的缓动参数。
-- 输出：
--   Accepted 表示是否接受命令；Reason 明示无效、过期或缺少 PrimaryPart。
-- 内部算法：
--   首次命令创建并缓存本地视觉副本，隐藏当前客户端的权威模型；
--   用服务器时间补偿延迟，再以原生 Tween 移动视觉副本的 PrimaryPart。
-- 副作用：
--   只改变当前客户端的视觉副本和 LocalTransparencyModifier；
--   不发送网络消息、不修改服务器模型状态。
local function present(command: VisualCommand): PresentResult
	local source = command.Model
	local record = recordsBySource[source] or createRecord(source)
	if not record then
		return {
			Accepted = false,
			Reason = "VisualModelUnavailable",
		}
	end
	if command.RequestId <= record.ActiveRequestId then
		return {
			Accepted = false,
			Reason = "StaleRequest",
		}
	end

	record.ActiveRequestId = command.RequestId
	if record.ActiveTween then
		local activeTween = record.ActiveTween
		record.ActiveTween = nil
		activeTween:Cancel()
		activeTween:Destroy()
	end

	local alpha = math.clamp(
		(workspace:GetServerTimeNow() - command.StartedAt) / command.Duration,
		0,
		1
	)
	local easedAlpha = TweenService:GetValue(
		alpha,
		command.EasingStyle,
		command.EasingDirection
	)
	local visualPivot = command.StartCFrame:Lerp(command.TargetCFrame, easedAlpha)
	record.VisualModel:PivotTo(visualPivot)
	if alpha >= 1 then
		return {
			Accepted = true,
			Reason = nil,
		}
	end

	local tween = TweenService:Create(
		record.PrimaryPart,
		TweenInfo.new(
			command.Duration * (1 - alpha),
			command.EasingStyle,
			command.EasingDirection
		),
		{
			CFrame = command.TargetCFrame * record.PivotToPrimary,
		}
	)
	record.ActiveTween = tween
	tween.Completed:Connect(function()
		if record.ActiveTween == tween then
			record.ActiveTween = nil
			tween:Destroy()
		end
	end)
	tween:Play()

	return {
		Accepted = true,
		Reason = nil,
	}
end

-- RemoteEvent 输入：单个严格 VisualCommand table。
-- RemoteEvent 输出：无；本地 PresentResult 只用于模块内部判断。
visualRemote.OnClientEvent:Connect(function(value)
	local command = validateCommand(value)
	if command then
		present(command)
	end
end)
