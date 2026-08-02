local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local TopDownCamera = {}

export type CameraState = {
	CameraType: Enum.CameraType,
	CameraSubject: Instance?,
	CFrame: CFrame,
	FieldOfView: number,
}

local function transitionTo(camera: Camera, targetCFrame: CFrame, targetFieldOfView: number, duration: number)
	local startCFrame = camera.CFrame
	local startFieldOfView = camera.FieldOfView
	local elapsed = 0

	camera.CameraType = Enum.CameraType.Scriptable

	while elapsed < duration do
		elapsed += RunService.RenderStepped:Wait()

		local alpha = math.min(elapsed / duration, 1)
		local easedAlpha = TweenService:GetValue(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = startCFrame:Lerp(targetCFrame, easedAlpha)
		camera.FieldOfView = startFieldOfView + (targetFieldOfView - startFieldOfView) * easedAlpha
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = targetCFrame
	camera.FieldOfView = targetFieldOfView
end

function TopDownCamera.Set(
	targetPart: BasePart,
	height: number,
	fieldOfView: number,
	transitionDuration: number
): CameraState
	assert(height > 0, "俯视相机高度必须大于 0")
	assert(transitionDuration > 0, "相机过渡时间必须大于 0")

	local camera = assert(workspace.CurrentCamera, "找不到 CurrentCamera")
	local previousState = {
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		CFrame = camera.CFrame,
		FieldOfView = camera.FieldOfView,
	}
	local targetPosition = targetPart.Position
	local cameraPosition = targetPosition + Vector3.new(0, height, 0)
	local targetCFrame = CFrame.lookAt(cameraPosition, targetPosition, Vector3.new(0, 0, -1))

	transitionTo(camera, targetCFrame, fieldOfView, transitionDuration)
	return previousState
end

function TopDownCamera.Restore(previousState: CameraState, transitionDuration: number)
	assert(transitionDuration > 0, "相机过渡时间必须大于 0")

	local camera = assert(workspace.CurrentCamera, "找不到 CurrentCamera")
	transitionTo(camera, previousState.CFrame, previousState.FieldOfView, transitionDuration)

	camera.CameraSubject = previousState.CameraSubject
	camera.CameraType = previousState.CameraType
end

return TopDownCamera
