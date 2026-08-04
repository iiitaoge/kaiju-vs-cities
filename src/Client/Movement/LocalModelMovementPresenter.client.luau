local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ModelMovementVisualProtocol = require(
	ReplicatedStorage.Shared.Movement.ModelMovementVisualProtocol
)

local visualRemote = ReplicatedStorage
	:WaitForChild("Remotes")
	:WaitForChild(ModelMovementVisualProtocol.RemoteName)
assert(
	visualRemote:IsA("RemoteEvent"),
	ModelMovementVisualProtocol.RemoteName .. " 必须是 RemoteEvent"
)

type VisualCommand = ModelMovementVisualProtocol.Command

type ActiveVisual = {
	StartCFrame: CFrame,
	TargetCFrame: CFrame,
	StartedAt: number,
	Duration: number,
	EasingStyle: Enum.EasingStyle,
	EasingDirection: Enum.EasingDirection,
}

export type PresentResult = {
	Accepted: boolean,
	Reason: string?,
}

local activeVisuals: { [Model]: ActiveVisual } = setmetatable({}, { __mode = "k" })
local latestRequestIds: { [Model]: number } = setmetatable({}, { __mode = "k" })

local function applyVisual(model: Model, visual: ActiveVisual): boolean
	if not model:IsDescendantOf(workspace) then
		return false
	end

	local alpha = math.clamp(
		(workspace:GetServerTimeNow() - visual.StartedAt) / visual.Duration,
		0,
		1
	)
	local easedAlpha = TweenService:GetValue(
		alpha,
		visual.EasingStyle,
		visual.EasingDirection
	)
	model:PivotTo(visual.StartCFrame:Lerp(visual.TargetCFrame, easedAlpha))
	return alpha < 1
end

-- 输入：
--   command.Model：服务器权威模型。
--   command.RequestId：该模型单调递增的视觉移动编号。
--   Move：服务器权威起止点、服务器时间、时长和缓动参数。
--   Cancel/Snap：服务器在终止旧插值后确认的权威 TargetCFrame。
-- 输出：
--   Accepted 表示是否接受命令；Reason 明示模型不可用或命令过期。
-- 内部算法：
--   按单调编号拒绝过期命令；Move 进入插值，Cancel/Snap 清理插值并立即校正。
-- 副作用：
--   只在当前客户端设置权威模型 Pivot；不 Clone、不改透明度、不发送网络消息。
local function present(command: VisualCommand): PresentResult
	local model = command.Model
	if not model:IsDescendantOf(workspace) then
		return {
			Accepted = false,
			Reason = "ModelUnavailable",
		}
	end

	local latestRequestId = latestRequestIds[model] or 0
	if command.RequestId <= latestRequestId then
		return {
			Accepted = false,
			Reason = "StaleRequest",
		}
	end

	latestRequestIds[model] = command.RequestId
	if command.Kind ~= ModelMovementVisualProtocol.Kinds.Move then
		activeVisuals[model] = nil
		model:PivotTo(command.TargetCFrame)
		return {
			Accepted = true,
			Reason = nil,
		}
	end

	local visual: ActiveVisual = {
		StartCFrame = command.StartCFrame,
		TargetCFrame = command.TargetCFrame,
		StartedAt = command.StartedAt,
		Duration = command.Duration,
		EasingStyle = command.EasingStyle,
		EasingDirection = command.EasingDirection,
	}
	activeVisuals[model] = visual
	if not applyVisual(model, visual) then
		activeVisuals[model] = nil
	end

	return {
		Accepted = true,
		Reason = nil,
	}
end

RunService.RenderStepped:Connect(function()
	for model, visual in activeVisuals do
		if not applyVisual(model, visual) and activeVisuals[model] == visual then
			activeVisuals[model] = nil
		end
	end
end)

-- RemoteEvent 输入：单个严格 VisualCommand table。
-- RemoteEvent 输出：无；本地 PresentResult 只用于模块内部判断。
visualRemote.OnClientEvent:Connect(function(value)
	local valid = ModelMovementVisualProtocol.Validate(value)
	if valid then
		present(value :: VisualCommand)
	end
end)
