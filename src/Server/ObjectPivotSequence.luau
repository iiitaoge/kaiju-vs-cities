--[[
	职责：按进度重叠播放一组服务器 BasePart/Model Pivot 动画。
	输入：显式目标 CFrame、时长、启动比例、缓动、可选跟随对象和取消检查。
	输出：整组是否完成及稳定失败原因。
	内部算法：Tween 一个 NumberValue；以同一缓动 Alpha 插值主对象，并保持跟随对象相对主对象的初始 Pivot。
	不负责：解析场景、计算沉入高度、修改锚定/碰撞、怪兽状态或业务顺序。
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ObjectPivotSequence = {}

export type PivotObject = BasePart | Model

export type Step = {
	Object: PivotObject,
	TargetCFrame: CFrame,
	Duration: number,
	StartNextAt: number?,
	EasingStyle: Enum.EasingStyle?,
	EasingDirection: Enum.EasingDirection?,
	Followers: { PivotObject }?,
}

export type PlayOptions = {
	IsCancelled: (() -> boolean)?,
	OnObjectStarted: ((index: number, object: PivotObject) -> ())?,
	OnObjectCompleted: ((index: number, object: PivotObject) -> ())?,
	OnCompleted: (() -> ())?,
}

export type PlayResult = {
	Succeeded: boolean,
	Reason: string?,
}

type ActiveRecord = {
	Alpha: NumberValue,
	Tween: Tween,
	PivotConnection: RBXScriptConnection,
	CompletedConnection: RBXScriptConnection?,
}

local function isPivotObject(value): boolean
	return typeof(value) == "Instance"
		and (value:IsA("BasePart") or value:IsA("Model"))
end

local function hasBasePart(object: PivotObject): boolean
	if object:IsA("BasePart") then
		return true
	end
	return object:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function getPivot(object: PivotObject): CFrame
	if object:IsA("BasePart") then
		return object.CFrame
	end
	return object:GetPivot()
end

local function pivotTo(object: PivotObject, targetCFrame: CFrame)
	if object:IsA("BasePart") then
		object.CFrame = targetCFrame
	else
		object:PivotTo(targetCFrame)
	end
end

local function validate(steps: { Step }, options: PlayOptions?)
	assert(type(steps) == "table" and #steps > 0, "运动序列不能为空")
	assert(options == nil or type(options) == "table", "options 必须是 table 或 nil")
	if options then
		assert(options.IsCancelled == nil or type(options.IsCancelled) == "function", "IsCancelled 必须是 function")
		assert(
			options.OnObjectStarted == nil or type(options.OnObjectStarted) == "function",
			"OnObjectStarted 必须是 function"
		)
		assert(
			options.OnObjectCompleted == nil or type(options.OnObjectCompleted) == "function",
			"OnObjectCompleted 必须是 function"
		)
		assert(options.OnCompleted == nil or type(options.OnCompleted) == "function", "OnCompleted 必须是 function")
	end

	local sequenceObjects: { [Instance]: boolean } = {}
	for index, step in steps do
		assert(type(step) == "table", string.format("第 %d 项必须是 table", index))
		assert(isPivotObject(step.Object), string.format("第 %d 项 Object 必须是 BasePart 或 Model", index))
		assert(step.Object.Parent ~= nil, string.format("第 %d 项 Object 必须已挂入数据树", index))
		assert(hasBasePart(step.Object), string.format("第 %d 项 Object 内没有 BasePart", index))
		assert(not sequenceObjects[step.Object], string.format("第 %d 项 Object 重复", index))
		assert(typeof(step.TargetCFrame) == "CFrame", string.format("第 %d 项 TargetCFrame 必须是 CFrame", index))
		assert(type(step.Duration) == "number" and step.Duration > 0, string.format("第 %d 项 Duration 必须大于 0", index))
		assert(step.Followers == nil or type(step.Followers) == "table", string.format("第 %d 项 Followers 必须是 table", index))
		if index < #steps then
			assert(
				type(step.StartNextAt) == "number"
					and step.StartNextAt >= 0
					and step.StartNextAt <= 1,
				string.format("第 %d 项 StartNextAt 必须在 0 到 1 之间", index)
			)
		end
		sequenceObjects[step.Object] = true
	end

	local usedFollowers: { [Instance]: boolean } = {}
	for index, step in steps do
		for followerIndex, follower in step.Followers or {} do
			assert(
				isPivotObject(follower),
				string.format("第 %d 项第 %d 个 Follower 必须是 BasePart 或 Model", index, followerIndex)
			)
			assert(follower.Parent ~= nil, string.format("第 %d 项 Follower 必须已挂入数据树", index))
			assert(hasBasePart(follower), string.format("第 %d 项 Follower 内没有 BasePart", index))
			assert(follower ~= step.Object, string.format("第 %d 项不能跟随自己", index))
			assert(not sequenceObjects[follower], string.format("第 %d 项 Follower 不能同时是序列 Object", index))
			assert(not usedFollowers[follower], string.format("第 %d 项 Follower 重复", index))
			usedFollowers[follower] = true
		end
	end
end

local function notify(callback, ...)
	if callback then
		task.spawn(callback, ...)
	end
end

-- 播放并等待整组运动结束。失败或取消会停止全部活动 Tween，不负责把对象复位。
function ObjectPivotSequence.Play(steps: { Step }, options: PlayOptions?): PlayResult
	validate(steps, options)

	local started: { [number]: boolean } = {}
	local active: { [number]: ActiveRecord } = {}
	local completedCount = 0
	local finished = false
	local finalResult: PlayResult? = nil
	local done = Instance.new("BindableEvent")
	local startStep

	local function cleanupRecord(index: number)
		local record = active[index]
		if not record then
			return
		end
		active[index] = nil
		record.PivotConnection:Disconnect()
		if record.CompletedConnection then
			record.CompletedConnection:Disconnect()
		end
		record.Tween:Destroy()
		record.Alpha:Destroy()
	end

	local function finish(succeeded: boolean, reason: string?)
		if finished then
			return
		end
		finished = true
		finalResult = {
			Succeeded = succeeded,
			Reason = reason,
		}
		for index, record in active do
			record.PivotConnection:Disconnect()
			if record.CompletedConnection then
				record.CompletedConnection:Disconnect()
			end
			record.Tween:Cancel()
			record.Tween:Destroy()
			record.Alpha:Destroy()
			active[index] = nil
		end
		done:Fire()
	end

	local function completeStep(index: number, object: PivotObject)
		if finished then
			return
		end
		completedCount += 1
		notify(options and options.OnObjectCompleted, index, object)
		if completedCount == #steps then
			if options and options.OnCompleted then
				options.OnCompleted()
			end
			finish(true, nil)
		end
	end

	startStep = function(index: number)
		if finished or index > #steps or started[index] then
			return
		end
		started[index] = true

		local step = steps[index]
		local object = step.Object
		if object.Parent == nil then
			finish(false, "ObjectRemoved")
			return
		end

		local startCFrame = getPivot(object)
		local targetCFrame = step.TargetCFrame
		local followerOffsets = {}
		for _, follower in step.Followers or {} do
			if follower.Parent == nil then
				finish(false, "FollowerRemoved")
				return
			end
			followerOffsets[follower] = startCFrame:ToObjectSpace(getPivot(follower))
		end

		notify(options and options.OnObjectStarted, index, object)

		if startCFrame == targetCFrame then
			pivotTo(object, targetCFrame)
			for follower, offset in followerOffsets do
				pivotTo(follower, targetCFrame * offset)
			end
			task.defer(startStep, index + 1)
			completeStep(index, object)
			return
		end

		local alpha = Instance.new("NumberValue")
		alpha.Value = 0
		local tween = TweenService:Create(
			alpha,
			TweenInfo.new(
				step.Duration,
				step.EasingStyle or Enum.EasingStyle.Sine,
				step.EasingDirection or Enum.EasingDirection.InOut
			),
			{ Value = 1 }
		)
		local record: ActiveRecord = {
			Alpha = alpha,
			Tween = tween,
			PivotConnection = nil :: any,
			CompletedConnection = nil,
		}
		active[index] = record

		record.PivotConnection = alpha:GetPropertyChangedSignal("Value"):Connect(function()
			if finished then
				return
			end
			if object.Parent == nil then
				finish(false, "ObjectRemoved")
				return
			end
			local currentCFrame = startCFrame:Lerp(targetCFrame, alpha.Value)
			pivotTo(object, currentCFrame)
			for follower, offset in followerOffsets do
				if follower.Parent == nil then
					finish(false, "FollowerRemoved")
					return
				end
				pivotTo(follower, currentCFrame * offset)
			end
			if index < #steps and alpha.Value >= (step.StartNextAt :: number) then
				startStep(index + 1)
			end
		end)

		record.CompletedConnection = tween.Completed:Connect(function(playbackState)
			if finished then
				return
			end
			if playbackState ~= Enum.PlaybackState.Completed then
				finish(false, "TweenInterrupted")
				return
			end
			pivotTo(object, targetCFrame)
			for follower, offset in followerOffsets do
				if follower.Parent == nil then
					finish(false, "FollowerRemoved")
					return
				end
				pivotTo(follower, targetCFrame * offset)
			end
			startStep(index + 1)
			cleanupRecord(index)
			completeStep(index, object)
		end)

		tween:Play()
		if index < #steps and (step.StartNextAt :: number) == 0 then
			task.defer(startStep, index + 1)
		end
	end

	if options and options.IsCancelled then
		task.spawn(function()
			while not finished do
				local succeeded, cancelled = pcall(options.IsCancelled :: () -> boolean)
				if not succeeded then
					finish(false, "CancellationCheckFailed")
					return
				end
				if cancelled then
					finish(false, "Cancelled")
					return
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end

	task.defer(startStep, 1)
	if not finished then
		done.Event:Wait()
	end
	done:Destroy()
	return finalResult :: PlayResult
end

return ObjectPivotSequence
