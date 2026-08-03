local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelMover = require(script.Parent.ModelMover)
local ValueValidation = require(ReplicatedStorage.Shared.ValueValidation)

local GodzillaMoveService = {}

export type MoveOptions = {
	-- 怪兽水平移动速度，单位为 studs/秒。
	MoveSpeed: number,
	-- 开始移动前的平滑转向时间，单位为秒。
	TurnDuration: number,
	-- 移动状态回调；true 开始移动，false 停止移动。
	SetMoving: (boolean) -> (),
}

local latestRequestIds = setmetatable({}, { __mode = "k" })

local function isValidPosition(position): boolean
	return ValueValidation.IsFiniteVector3(position)
end

local function validateInputs(model: Model, options: MoveOptions)
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.MoveSpeed) == "number" and options.MoveSpeed > 0, "MoveSpeed 必须是大于 0 的 number")
	assert(
		type(options.TurnDuration) == "number" and options.TurnDuration > 0,
		"TurnDuration 必须是大于 0 的 number"
	)
	assert(type(options.SetMoving) == "function", "SetMoving 必须是 function")
end

local function makeTargetCFrame(model: Model, clickedPosition: Vector3): CFrame
	local currentPivot = model:GetPivot()
	local targetPosition = Vector3.new(clickedPosition.X, currentPivot.Position.Y, clickedPosition.Z)
	local horizontalDirection = targetPosition - currentPivot.Position

	if horizontalDirection.Magnitude == 0 then
		return CFrame.new(targetPosition) * currentPivot.Rotation
	end

	return CFrame.lookAt(targetPosition, targetPosition + horizontalDirection.Unit)
end

-- 输入：
--   model：需要移动的怪兽模型。
--   clickedPosition：目标世界坐标；只采用 X/Z，Y 保持模型当前高度。
--   options：移动速度、转向时间和显式移动状态回调。
-- 输出：
--   完整转向并到达目标时返回 true；输入无效、被新请求取消或 Tween 中断时返回 false。
-- 副作用：移动模型，并通过 SetMoving 报告移动状态。
function GodzillaMoveService.MoveTo(
	model: Model,
	clickedPosition: Vector3,
	options: MoveOptions
): boolean
	validateInputs(model, options)
	if not isValidPosition(clickedPosition) then
		return false
	end

	local requestId = (latestRequestIds[model] or 0) + 1
	latestRequestIds[model] = requestId

	local targetCFrame = makeTargetCFrame(model, clickedPosition)

	options.SetMoving(false)
	local turned = ModelMover.TurnTo(model, targetCFrame, options.TurnDuration)
	if not turned or latestRequestIds[model] ~= requestId then
		return false
	end

	options.SetMoving(true)
	local completed = ModelMover.MoveTo(model, targetCFrame, options.MoveSpeed)

	if latestRequestIds[model] == requestId then
		options.SetMoving(false)
	end

	return completed
end

-- 输入：
--   model：需要转向的怪兽模型。
--   lookAtPosition：要面对的世界坐标；只采用 X/Z。
--   turnDuration：平滑转向时间，单位为秒。
-- 输出：
--   转向完成且没有被更新请求取消时返回 true，否则返回 false。
-- 副作用：只旋转模型，不改变模型位置，也不播放动画。
function GodzillaMoveService.FaceTo(
	model: Model,
	lookAtPosition: Vector3,
	turnDuration: number
): boolean
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(
		type(turnDuration) == "number" and turnDuration > 0,
		"turnDuration 必须是大于 0 的 number"
	)
	if not isValidPosition(lookAtPosition) then
		return false
	end

	local requestId = (latestRequestIds[model] or 0) + 1
	latestRequestIds[model] = requestId

	local currentPivot = model:GetPivot()
	local horizontalTarget = Vector3.new(
		lookAtPosition.X,
		currentPivot.Position.Y,
		lookAtPosition.Z
	)
	local horizontalDirection = horizontalTarget - currentPivot.Position
	local facingCFrame = if horizontalDirection.Magnitude == 0
		then CFrame.new(currentPivot.Position) * currentPivot.Rotation
		else CFrame.lookAt(
			currentPivot.Position,
			currentPivot.Position + horizontalDirection.Unit
		)
	local completed = ModelMover.TurnTo(model, facingCFrame, turnDuration)
	return completed and latestRequestIds[model] == requestId
end

-- 输入：怪兽模型。
-- 输出：是否取消了一条活动移动。
-- 副作用：使当前 MoveTo / FaceTo 请求失效，并停止底层 Tween。
function GodzillaMoveService.Cancel(model: Model): boolean
	assert(model:IsA("Model"), "model 必须是 Model")
	latestRequestIds[model] = (latestRequestIds[model] or 0) + 1
	return ModelMover.Cancel(model)
end

return GodzillaMoveService
