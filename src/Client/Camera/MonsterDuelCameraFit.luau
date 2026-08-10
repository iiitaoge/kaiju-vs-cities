--[[
	职责：根据客户端屏幕比例计算决斗镜头需要向后拉远的距离。
	输入：CameraMarker 基础 CFrame、垂直 FOV、ViewportSize 和怪兽包围球。
	输出：保持 CameraMarker 朝向不变、且能容纳全部包围球的 CFrame。
	内部算法：把包围球投影到 CameraMarker 的局部坐标，分别按水平/垂直半 FOV
	计算所需深度，取最大值作为沿 LookVector 反方向的拉远距离。
	不负责：修改 FOV、改变镜头朝向、移动怪兽或选择场景。
]]

local MonsterDuelCameraFit = {}

export type FitSphere = {
	Center: Vector3,
	Radius: number,
}

local function isFiniteNumber(value: number): boolean
	return value == value and value < math.huge and value > -math.huge
end

function MonsterDuelCameraFit.Fit(
	baseCFrame: CFrame,
	fieldOfView: number,
	viewportSize: Vector2,
	spheres: { FitSphere },
	padding: number
): CFrame
	assert(typeof(baseCFrame) == "CFrame", "baseCFrame 必须是 CFrame")
	assert(
		type(fieldOfView) == "number"
			and isFiniteNumber(fieldOfView)
			and fieldOfView > 0
			and fieldOfView < 180,
		"fieldOfView 必须在 0 到 180 之间"
	)
	assert(typeof(viewportSize) == "Vector2", "viewportSize 必须是 Vector2")
	assert(type(spheres) == "table" and #spheres > 0, "spheres 必须是非空数组")
	assert(
		type(padding) == "number"
			and isFiniteNumber(padding)
			and padding >= 1,
		"padding 必须是大于等于 1 的 number"
	)

	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return baseCFrame
	end

	local verticalHalfFovTangent = math.tan(math.rad(fieldOfView * 0.5))
	local horizontalHalfFovTangent = verticalHalfFovTangent
		* (viewportSize.X / viewportSize.Y)
	local pullback = 0

	for _, sphere in spheres do
		assert(typeof(sphere.Center) == "Vector3", "FitSphere.Center 必须是 Vector3")
		assert(
			type(sphere.Radius) == "number"
				and isFiniteNumber(sphere.Radius)
				and sphere.Radius > 0,
			"FitSphere.Radius 必须是正数"
		)

		local localCenter = baseCFrame:PointToObjectSpace(sphere.Center)
		local nearestDepth = -localCenter.Z - sphere.Radius
		local horizontalExtent = (math.abs(localCenter.X) + sphere.Radius) * padding
		local verticalExtent = (math.abs(localCenter.Y) + sphere.Radius) * padding

		pullback = math.max(
			pullback,
			horizontalExtent / horizontalHalfFovTangent - nearestDepth,
			verticalExtent / verticalHalfFovTangent - nearestDepth,
			-nearestDepth
		)
	end

	pullback = math.max(0, pullback)
	local position = baseCFrame.Position - baseCFrame.LookVector * pullback
	return CFrame.new(position) * baseCFrame.Rotation
end

return table.freeze(MonsterDuelCameraFit)
