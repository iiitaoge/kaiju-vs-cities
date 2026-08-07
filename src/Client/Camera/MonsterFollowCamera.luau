local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MonsterFollowCamera = {}

export type FocusOptions = {
	TargetCFrame: CFrame,
	TransitionDuration: number,
	FieldOfView: number?,
	OnCompleted: (() -> ())?,
}

export type FollowOptions = {
	-- 相对于怪兽 Pivot 朝向的相机偏移。
	Offset: Vector3,
	FieldOfView: number,
	Responsiveness: number,
	RestoreDuration: number?,
	OnStopped: ((string) -> ())?,
}

export type Session = {
	Stop: (string?) -> (),
	Focus: (FocusOptions) -> boolean,
	IsActive: () -> boolean,
}

-- 输入：需要跟随的 Workspace 怪兽、跟随参数，以及可选的区域 Marker 运镜参数。
-- 输出：可手动停止或切换到 Marker 的本地相机会话。
-- 内部算法：一个会话独占 CurrentCamera；跟随、Marker 过渡和恢复都在同一个 RenderStepped 循环中执行。
function MonsterFollowCamera.Start(model: Model, options: FollowOptions): Session
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(typeof(options.Offset) == "Vector3", "Offset 必须是 Vector3")
	assert(
		type(options.FieldOfView) == "number" and options.FieldOfView > 0,
		"FieldOfView 必须大于 0"
	)
	assert(
		type(options.Responsiveness) == "number" and options.Responsiveness > 0,
		"Responsiveness 必须大于 0"
	)
	assert(
		options.RestoreDuration == nil
			or (type(options.RestoreDuration) == "number" and options.RestoreDuration >= 0),
		"RestoreDuration 必须大于等于 0 或 nil"
	)

	local camera = assert(workspace.CurrentCamera, "找不到 CurrentCamera")
	local previous = {
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		CFrame = camera.CFrame,
		FieldOfView = camera.FieldOfView,
	}
	local active = true
	local stopping = false
	local phase: "Following" | "Transitioning" | "Marker" | "Restoring" = "Following"
	local transition = nil :: {
		StartCFrame: CFrame,
		TargetCFrame: CFrame,
		StartFieldOfView: number,
		TargetFieldOfView: number,
		Duration: number,
		Elapsed: number,
		OnCompleted: () -> (),
	}?
	local connection: RBXScriptConnection? = nil

	local function finishStop(reason: string)
		if not active then
			return
		end
		active = false
		stopping = false
		transition = nil
		if connection then
			connection:Disconnect()
			connection = nil
		end
		camera.CameraType = previous.CameraType
		camera.CameraSubject = previous.CameraSubject
		camera.CFrame = previous.CFrame
		camera.FieldOfView = previous.FieldOfView
		if options.OnStopped then
			options.OnStopped(reason or "Stopped")
		end
	end

	local function beginTransition(
		targetCFrame: CFrame,
		targetFieldOfView: number,
		duration: number,
		onCompleted: () -> ()
	)
		transition = {
			StartCFrame = camera.CFrame,
			TargetCFrame = targetCFrame,
			StartFieldOfView = camera.FieldOfView,
			TargetFieldOfView = targetFieldOfView,
			Duration = duration,
			Elapsed = 0,
			OnCompleted = onCompleted,
		}
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local function stop(reason: string?)
		if not active or stopping then
			return
		end
		stopping = true
		phase = "Restoring"
		local restoreDuration = options.RestoreDuration or 0
		if restoreDuration <= 0 then
			finishStop(reason or "Stopped")
			return
		end
		beginTransition(
			previous.CFrame,
			previous.FieldOfView,
			restoreDuration,
			function()
				finishStop(reason or "Stopped")
			end
		)
	end

	local function focus(focusOptions: FocusOptions): boolean
		if not active or stopping then
			return false
		end
		assert(typeof(focusOptions.TargetCFrame) == "CFrame", "TargetCFrame 必须是 CFrame")
		assert(
			type(focusOptions.TransitionDuration) == "number"
				and focusOptions.TransitionDuration >= 0,
			"TransitionDuration 必须大于等于 0"
		)
		assert(
			focusOptions.FieldOfView == nil
				or (type(focusOptions.FieldOfView) == "number"
					and focusOptions.FieldOfView > 0
					and focusOptions.FieldOfView < 180),
			"FieldOfView 必须在 0 到 180 之间或 nil"
		)

		phase = "Transitioning"
		local targetFieldOfView = focusOptions.FieldOfView or camera.FieldOfView
		beginTransition(
			focusOptions.TargetCFrame,
			targetFieldOfView,
			focusOptions.TransitionDuration,
			function()
				phase = "Marker"
				if focusOptions.OnCompleted then
					focusOptions.OnCompleted()
				end
			end
		)
		return true
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = options.FieldOfView
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		if phase ~= "Restoring" and not model:IsDescendantOf(workspace) then
			stop("MonsterUnavailable")
			return
		end
		if transition then
			local currentTransition = transition
			currentTransition.Elapsed += deltaTime
			local alpha = if currentTransition.Duration <= 0
				then 1
				else math.clamp(currentTransition.Elapsed / currentTransition.Duration, 0, 1)
			local easedAlpha = TweenService:GetValue(
				alpha,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			)
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = currentTransition.StartCFrame:Lerp(
				currentTransition.TargetCFrame,
				easedAlpha
			)
			camera.FieldOfView = currentTransition.StartFieldOfView
				+ (currentTransition.TargetFieldOfView - currentTransition.StartFieldOfView)
					* easedAlpha
			if alpha >= 1 and transition == currentTransition then
				transition = nil
				currentTransition.OnCompleted()
			end
			return
		end
		if phase == "Marker" then
			camera.CameraType = Enum.CameraType.Scriptable
			return
		end
		if phase == "Restoring" then
			return
		end
		local pivot = model:GetPivot()
		local focus = pivot.Position
		local cameraPosition = focus + pivot:VectorToWorldSpace(options.Offset)
		local target = CFrame.lookAt(cameraPosition, focus)
		local alpha = 1 - math.exp(-options.Responsiveness * deltaTime)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camera.CFrame:Lerp(target, alpha)
		camera.FieldOfView = options.FieldOfView
	end)

	return {
		Stop = stop,
		Focus = focus,
		IsActive = function()
			return active
		end,
	}
end

return MonsterFollowCamera
