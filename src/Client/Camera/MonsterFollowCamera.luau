local RunService = game:GetService("RunService")

local MonsterFollowCamera = {}

export type FollowOptions = {
	-- 相对于怪兽 Pivot 朝向的相机偏移。
	Offset: Vector3,
	FieldOfView: number,
	Responsiveness: number,
	OnStopped: ((string) -> ())?,
}

export type Session = {
	Stop: (string?) -> (),
	IsActive: () -> boolean,
}

-- 输入：需要跟随的 Workspace 怪兽和显式相机参数。
-- 输出：可手动停止的本地跟随会话。
-- 内部算法：保存原相机状态，每帧平滑追随怪兽；模型消失时自动恢复。
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

	local camera = assert(workspace.CurrentCamera, "找不到 CurrentCamera")
	local previous = {
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		CFrame = camera.CFrame,
		FieldOfView = camera.FieldOfView,
	}
	local active = true
	local connection: RBXScriptConnection? = nil

	local function stop(reason: string?)
		if not active then
			return
		end
		active = false
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

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = options.FieldOfView
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		if not model:IsDescendantOf(workspace) then
			stop("MonsterUnavailable")
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
		IsActive = function()
			return active
		end,
	}
end

return MonsterFollowCamera
