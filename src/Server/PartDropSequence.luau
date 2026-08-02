local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PartDropSequence = {}

export type DropObject = BasePart | Model

export type Step = {
	Object: DropObject,
	Target: BasePart,
	Duration: number,
	StartNextAt: number?,
	EasingStyle: Enum.EasingStyle?,
	EasingDirection: Enum.EasingDirection?,
}

export type PlayOptions = {
	OnObjectStarted: ((index: number, object: DropObject) -> ())?,
	OnObjectCompleted: ((index: number, object: DropObject) -> ())?,
	OnCompleted: (() -> ())?,
}

local function isDropObject(instance: Instance): boolean
	return instance:IsA("BasePart") or instance:IsA("Model")
end

local function getObjectParts(object: DropObject): { BasePart }
	if object:IsA("BasePart") then
		return { object }
	end

	local parts = {}
	for _, descendant in object:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function validateSteps(steps: { Step })
	assert(#steps > 0, "下降序列不能为空")

	local usedObjects: { [Instance]: boolean } = {}
	for index, step in steps do
		assert(isDropObject(step.Object), string.format("第 %d 项的 Object 必须是 BasePart 或 Model", index))
		assert(step.Target:IsA("BasePart"), string.format("第 %d 项的 Target 必须是 BasePart", index))
		assert(step.Object ~= step.Target, string.format("第 %d 项不能把自己设为目标", index))
		assert(
			not step.Target:IsDescendantOf(step.Object),
			string.format("第 %d 项的 Target 不能位于 Object 内部", index)
		)
		assert(#getObjectParts(step.Object) > 0, string.format("第 %d 项的 Model 内没有 BasePart", index))
		assert(not usedObjects[step.Object], string.format("第 %d 项的 Object 在序列中重复出现", index))
		assert(step.Duration > 0, string.format("第 %d 项的 Duration 必须大于 0", index))

		if index < #steps then
			local startNextAt = step.StartNextAt
			assert(startNextAt ~= nil, string.format("第 %d 项缺少 StartNextAt", index))
			assert(
				startNextAt >= 0 and startNextAt <= 1,
				string.format("第 %d 项的 StartNextAt 必须在 0 到 1 之间", index)
			)
		end

		usedObjects[step.Object] = true
	end
end

local function getPartHighestY(part: BasePart): number
	local cframe = part.CFrame
	local size = part.Size
	local verticalHalfExtent = (
		math.abs(cframe.RightVector.Y) * size.X
		+ math.abs(cframe.UpVector.Y) * size.Y
		+ math.abs(cframe.LookVector.Y) * size.Z
	) / 2

	return cframe.Position.Y + verticalHalfExtent
end

local function getObjectHighestY(object: DropObject): number
	local highestY = -math.huge
	for _, part in getObjectParts(object) do
		highestY = math.max(highestY, getPartHighestY(part))
	end

	return highestY
end

local function getObjectPivot(object: DropObject): CFrame
	if object:IsA("BasePart") then
		return object.CFrame
	end

	return object:GetPivot()
end

local function pivotObject(object: DropObject, targetCFrame: CFrame)
	if object:IsA("BasePart") then
		object.CFrame = targetCFrame
	else
		object:PivotTo(targetCFrame)
	end
end

local function anchorObject(object: DropObject)
	for _, part in getObjectParts(object) do
		part.Anchored = true
	end
end

local function resolveTargetCFrames(steps: { Step }): { CFrame }
	local targetCFrames = {}
	for index, step in steps do
		local startCFrame = getObjectPivot(step.Object)
		local verticalOffset = getPartHighestY(step.Target) - getObjectHighestY(step.Object)
		assert(
			verticalOffset <= 0,
			string.format("第 %d 项的目标高度高于下降 Object", index)
		)

		targetCFrames[index] = startCFrame + Vector3.new(0, verticalOffset, 0)
	end

	return targetCFrames
end

local function notify(
	callback: ((index: number, object: DropObject) -> ())?,
	index: number,
	object: DropObject
)
	if callback then
		task.spawn(callback, index, object)
	end
end

-- 播放并等待整组下降完成；目标高度在调用时确定，本模块不负责复位。
function PartDropSequence.Play(steps: { Step }, options: PlayOptions?)
	validateSteps(steps)
	local targetCFrames = resolveTargetCFrames(steps)

	local stepCount = #steps
	local started: { [number]: boolean } = {}
	local completedCount = 0
	local allCompleted = Instance.new("BindableEvent")

	local function completeStep(index: number, object: DropObject)
		completedCount += 1
		notify(options and options.OnObjectCompleted, index, object)

		if completedCount == stepCount then
			allCompleted:Fire()
		end
	end

	local function startStep(index: number)
		if index > stepCount or started[index] then
			return
		end
		started[index] = true

		local step = steps[index]
		local object = step.Object
		local startCFrame = getObjectPivot(object)
		local targetCFrame = targetCFrames[index]

		anchorObject(object)
		notify(options and options.OnObjectStarted, index, object)

		local totalDistance = startCFrame.Position.Y - targetCFrame.Position.Y
		if totalDistance == 0 then
			completeStep(index, object)
			task.defer(startStep, index + 1)
			return
		end

		local pivotValue = Instance.new("CFrameValue")
		pivotValue.Value = startCFrame
		local pivotConnection = pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
			pivotObject(object, pivotValue.Value)
		end)

		local tween = TweenService:Create(
			pivotValue,
			TweenInfo.new(
				step.Duration,
				step.EasingStyle or Enum.EasingStyle.Sine,
				step.EasingDirection or Enum.EasingDirection.InOut
			),
			{ Value = targetCFrame }
		)
		tween:Play()

		if index < stepCount then
			local startNextAt = step.StartNextAt :: number
			task.spawn(function()
				while tween.PlaybackState == Enum.PlaybackState.Playing do
					local movedDistance = startCFrame.Position.Y - getObjectPivot(object).Position.Y
					if movedDistance / totalDistance >= startNextAt then
						startStep(index + 1)
						return
					end

					RunService.Heartbeat:Wait()
				end

				startStep(index + 1)
			end)
		end

		task.spawn(function()
			local playbackState = tween.Completed:Wait()
			if playbackState == Enum.PlaybackState.Completed then
				pivotObject(object, targetCFrame)
			end

			pivotConnection:Disconnect()
			pivotValue:Destroy()
			tween:Destroy()
			completeStep(index, object)
		end)
	end

	task.spawn(startStep, 1)
	allCompleted.Event:Wait()
	allCompleted:Destroy()

	if options and options.OnCompleted then
		options.OnCompleted()
	end
end

return PartDropSequence
