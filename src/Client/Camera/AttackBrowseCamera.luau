local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AttackBrowseCamera = {}

export type AttackView = {
	CFrame: CFrame,
	Size: Vector3,
}

export type Options = {
	FieldOfView: number,
	PaddingRatio: number,
	TransitionDuration: number,
	RestoreDuration: number,
}

export type Session = {
	SetTarget: (AttackView) -> boolean,
	Restore: () -> boolean,
	IsActive: () -> boolean,
}

local function isValidView(view: AttackView): boolean
	return type(view) == "table"
		and typeof(view.CFrame) == "CFrame"
		and typeof(view.Size) == "Vector3"
		and view.Size.X > 0
		and view.Size.Z > 0
end

-- 输入：单个 Plot 总范围、相机 FOV、屏幕比例和显式边距。
-- 输出：完整容纳总范围的俯视 CFrame。
-- 内部算法：分别计算容纳范围宽度和深度所需高度，采用较大值。
local function targetCFrame(
	camera: Camera,
	view: AttackView,
	fieldOfView: number,
	paddingRatio: number
): CFrame
	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 0 then math.max(viewport.X / viewport.Y, 0.01) else 1
	local tangent = math.tan(math.rad(fieldOfView) * 0.5)
	local scale = 1 + paddingRatio
	local heightForDepth = view.Size.Z * 0.5 * scale / tangent
	local heightForWidth = view.Size.X * 0.5 * scale / (tangent * aspect)
	local height = math.max(heightForDepth, heightForWidth)

	local focus = view.CFrame.Position
	local forward = view.CFrame.LookVector
	local screenUp = Vector3.new(forward.X, 0, forward.Z)
	if screenUp.Magnitude < 0.001 then
		screenUp = Vector3.new(0, 0, -1)
	else
		screenUp = screenUp.Unit
	end
	return CFrame.lookAt(focus + Vector3.new(0, height, 0), focus, screenUp)
end

-- 输入：首个目标 Plot 的总攻击视野和显式相机参数。
-- 输出：可反复切换目标并最终恢复原视角的会话。
-- 切换玩家不会覆盖打开面板前保存的原相机状态。
function AttackBrowseCamera.Open(initialView: AttackView, options: Options): Session
	assert(isValidView(initialView), "initialView 必须是有效 AttackView")
	assert(type(options) == "table", "options 必须是 table")
	assert(
		type(options.FieldOfView) == "number"
			and options.FieldOfView > 0
			and options.FieldOfView < 180,
		"FieldOfView 必须在 0 到 180 之间"
	)
	assert(
		type(options.PaddingRatio) == "number" and options.PaddingRatio >= 0,
		"PaddingRatio 必须大于等于 0"
	)
	assert(
		type(options.TransitionDuration) == "number" and options.TransitionDuration >= 0,
		"TransitionDuration 必须大于等于 0"
	)
	assert(
		type(options.RestoreDuration) == "number" and options.RestoreDuration >= 0,
		"RestoreDuration 必须大于等于 0"
	)

	local camera = assert(workspace.CurrentCamera, "找不到 CurrentCamera")
	local previous = {
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		CFrame = camera.CFrame,
		FieldOfView = camera.FieldOfView,
	}
	local active = true
	local requestId = 0

	local function transition(cframe: CFrame, fieldOfView: number, duration: number): boolean
		requestId += 1
		local ownRequestId = requestId
		local startCFrame = camera.CFrame
		local startFieldOfView = camera.FieldOfView
		local elapsed = 0
		camera.CameraType = Enum.CameraType.Scriptable

		while active and ownRequestId == requestId and elapsed < duration do
			elapsed += RunService.RenderStepped:Wait()
			local alpha = math.min(elapsed / duration, 1)
			local eased = TweenService:GetValue(
				alpha,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			)
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = startCFrame:Lerp(cframe, eased)
			camera.FieldOfView = startFieldOfView
				+ (fieldOfView - startFieldOfView) * eased
		end
		if not active or ownRequestId ~= requestId then
			return false
		end
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cframe
		camera.FieldOfView = fieldOfView
		return true
	end

	local function setTarget(view: AttackView): boolean
		if not active or not isValidView(view) then
			return false
		end
		return transition(
			targetCFrame(camera, view, options.FieldOfView, options.PaddingRatio),
			options.FieldOfView,
			options.TransitionDuration
		)
	end

	local function restore(): boolean
		if not active then
			return false
		end
		local restored = transition(
			previous.CFrame,
			previous.FieldOfView,
			options.RestoreDuration
		)
		active = false
		requestId += 1
		camera.CameraSubject = previous.CameraSubject
		camera.CameraType = previous.CameraType
		return restored
	end

	setTarget(initialView)
	return {
		SetTarget = setTarget,
		Restore = restore,
		IsActive = function()
			return active
		end,
	}
end

return AttackBrowseCamera
