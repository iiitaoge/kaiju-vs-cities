local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local ModelMovementVisualProtocol = require(
	ReplicatedStorage.Shared.Movement.ModelMovementVisualProtocol
)

local ModelMover = {}

local activeTweens = setmetatable({}, { __mode = "k" })
local latestVisualRequestIds = setmetatable({}, { __mode = "k" })

local visualRemote = ServerRemoteAccess.EnsureEvent(
	ModelMovementVisualProtocol.RemoteName
)

local function nextVisualRequestId(model: Model): number
	local requestId = (latestVisualRequestIds[model] or 0) + 1
	latestVisualRequestIds[model] = requestId
	return requestId
end

local function cancelActiveTween(model: Model): boolean
	local tween = activeTweens[model]
	if not tween then
		return false
	end
	activeTweens[model] = nil
	tween:Cancel()
	return true
end

local function publishTerminal(
	model: Model,
	kind: "Cancel" | "Snap",
	targetCFrame: CFrame
)
	visualRemote:FireAllClients({
		Kind = kind,
		Model = model,
		RequestId = nextVisualRequestId(model),
		TargetCFrame = targetCFrame,
	})
end

local function disableCollisions(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
		end
	end
end

local function tweenPivot(
	model: Model,
	targetCFrame: CFrame,
	duration: number,
	easingStyle: Enum.EasingStyle,
	easingDirection: Enum.EasingDirection
): boolean
	local previousTween = activeTweens[model]
	if previousTween then
		cancelActiveTween(model)
	end

	local startCFrame = model:GetPivot()
	if duration == 0 then
		model:PivotTo(targetCFrame)
		publishTerminal(
			model,
			ModelMovementVisualProtocol.Kinds.Snap,
			targetCFrame
		)
		return true
	end

	local visualRequestId = nextVisualRequestId(model)
	local startedAt = workspace:GetServerTimeNow()
	-- 输入：
	--   model、唯一请求编号、权威起止 CFrame、服务器开始时间、时长和缓动参数。
	-- 输出：无返回值；所有客户端获得同一条只读视觉移动命令。
	-- 副作用：不接受客户端数据，不改变服务器移动结果。
	visualRemote:FireAllClients({
		Kind = ModelMovementVisualProtocol.Kinds.Move,
		Model = model,
		RequestId = visualRequestId,
		StartCFrame = startCFrame,
		TargetCFrame = targetCFrame,
		StartedAt = startedAt,
		Duration = duration,
		EasingStyle = easingStyle,
		EasingDirection = easingDirection,
	})

	local pivotValue = Instance.new("CFrameValue")
	pivotValue.Value = startCFrame

	local connection = pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
		model:PivotTo(pivotValue.Value)
	end)

	local tween = TweenService:Create(
		pivotValue,
		TweenInfo.new(duration, easingStyle, easingDirection),
		{ Value = targetCFrame }
	)
	activeTweens[model] = tween

	tween:Play()
	local playbackState = tween.Completed:Wait()

	connection:Disconnect()
	pivotValue:Destroy()

	if activeTweens[model] == tween then
		activeTweens[model] = nil
	end

	return playbackState == Enum.PlaybackState.Completed
end

-- 输入：model、只用于确定朝向的 targetCFrame、转向时长。
-- 输出：服务器权威模型完成转向时返回 true；被新移动取消时返回 false。
-- 副作用：关闭模型碰撞、更新服务器权威 Pivot，并广播客户端视觉转向命令。
function ModelMover.TurnTo(model: Model, targetCFrame: CFrame, duration: number): boolean
	assert(duration > 0, "转向时间必须大于 0")

	disableCollisions(model)

	local currentPosition = model:GetPivot().Position
	local turnCFrame = CFrame.new(currentPosition) * targetCFrame.Rotation
	return tweenPivot(
		model,
		turnCFrame,
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)
end

-- 输入：model、包含最终位置和朝向的 targetCFrame、移动速度。
-- 输出：服务器权威模型到达目标时返回 true；被新移动取消时返回 false。
-- 副作用：关闭模型碰撞、更新服务器权威 Pivot，并广播客户端视觉移动命令。
function ModelMover.MoveTo(model: Model, targetCFrame: CFrame, speed: number): boolean
	assert(speed > 0, "移动速度必须大于 0")

	disableCollisions(model)

	local startCFrame = model:GetPivot()
	local distance = (targetCFrame.Position - startCFrame.Position).Magnitude
	return tweenPivot(
		model,
		targetCFrame,
		distance / speed,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.InOut
	)
end

-- 输入：正在转向或移动的服务器模型。
-- 输出：是否取消了一条活动 Tween。
-- 副作用：停止当前权威移动，并广播更高编号的 Cancel 让所有客户端清除旧插值。
function ModelMover.Cancel(model: Model): boolean
	local cancelled = cancelActiveTween(model)
	publishTerminal(
		model,
		ModelMovementVisualProtocol.Kinds.Cancel,
		model:GetPivot()
	)
	return cancelled
end

-- 输入：服务器模型和确定的最终 CFrame。
-- 输出：模型仍存在时完成瞬移并返回 true。
-- 副作用：取消旧 Tween、写入权威 Pivot，并广播 Snap 终止每个客户端的旧插值。
function ModelMover.Snap(model: Model, targetCFrame: CFrame): boolean
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(typeof(targetCFrame) == "CFrame", "targetCFrame 必须是 CFrame")
	cancelActiveTween(model)
	disableCollisions(model)
	model:PivotTo(targetCFrame)
	publishTerminal(
		model,
		ModelMovementVisualProtocol.Kinds.Snap,
		targetCFrame
	)
	return true
end

return ModelMover
