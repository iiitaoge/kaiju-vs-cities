--[[
	职责：计算两个水平有向包围盒的边缘距离，以及移动对象面向目标时的站位。
	输入：只包含 Pivot、包围盒 CFrame/Size 的纯数据和非负期望间距。
	输出：非负水平边缘距离，或保持移动对象 Pivot 高度的目标位置与朝向点。
	内部算法：沿中心连线计算两个有向包围盒的支撑半径，并补偿 Bounds 相对 Pivot 的偏移。
	不负责：读取 Model、查询 Workspace、移动对象或解释目标身份。
]]

local HorizontalBoundsGeometry = {}

local EPSILON = 1e-6

export type Bounds = {
	CFrame: CFrame,
	Size: Vector3,
}

export type MovingBounds = {
	Pivot: CFrame,
	CFrame: CFrame,
	Size: Vector3,
}

export type Pose = {
	Position: Vector3,
	LookAtPosition: Vector3,
}

local function horizontal(vector: Vector3): Vector2
	return Vector2.new(vector.X, vector.Z)
end

local function unitOrFallback(vector: Vector2, fallback: Vector2): Vector2
	if vector.Magnitude > EPSILON then
		return vector.Unit
	end
	if fallback.Magnitude > EPSILON then
		return fallback.Unit
	end
	return Vector2.new(0, 1)
end

local function assertBounds(bounds: Bounds, name: string)
	assert(type(bounds) == "table", name .. " 必须是 Bounds")
	assert(typeof(bounds.CFrame) == "CFrame", name .. ".CFrame 必须是 CFrame")
	assert(typeof(bounds.Size) == "Vector3", name .. ".Size 必须是 Vector3")
end

local function supportRadius(cframe: CFrame, size: Vector3, direction: Vector2): number
	local right = unitOrFallback(horizontal(cframe.RightVector), Vector2.new(1, 0))
	local look = unitOrFallback(horizontal(cframe.LookVector), Vector2.new(0, 1))
	return math.abs(direction:Dot(right)) * size.X * 0.5
		+ math.abs(direction:Dot(look)) * size.Z * 0.5
end

function HorizontalBoundsGeometry.GetGap(
	first: Bounds,
	second: Bounds,
	fallbackDirection: Vector3
): number
	assertBounds(first, "first")
	assertBounds(second, "second")
	assert(typeof(fallbackDirection) == "Vector3", "fallbackDirection 必须是 Vector3")

	local firstCenter = horizontal(first.CFrame.Position)
	local secondCenter = horizontal(second.CFrame.Position)
	local direction = unitOrFallback(
		secondCenter - firstCenter,
		horizontal(fallbackDirection)
	)
	local centerDistance = (secondCenter - firstCenter).Magnitude
	local firstRadius = supportRadius(first.CFrame, first.Size, direction)
	local secondRadius = supportRadius(second.CFrame, second.Size, direction)
	return math.max(0, centerDistance - firstRadius - secondRadius)
end

function HorizontalBoundsGeometry.ResolvePose(
	moving: MovingBounds,
	target: Bounds,
	desiredGap: number
): Pose
	assertBounds(moving, "moving")
	assert(typeof(moving.Pivot) == "CFrame", "moving.Pivot 必须是 CFrame")
	assertBounds(target, "target")
	assert(type(desiredGap) == "number" and desiredGap >= 0, "desiredGap 必须大于等于 0")

	local targetCenter = horizontal(target.CFrame.Position)
	local movingCenter = horizontal(moving.CFrame.Position)
	local away = unitOrFallback(
		movingCenter - targetCenter,
		-horizontal(moving.Pivot.LookVector)
	)
	local relativeBounds = moving.Pivot:ToObjectSpace(moving.CFrame)
	local facingRotation = CFrame.lookAt(
		Vector3.zero,
		Vector3.new(-away.X, 0, -away.Y)
	).Rotation
	local targetMovingBoundsRotation = facingRotation * relativeBounds.Rotation
	local rotatedOffset = horizontal(
		facingRotation:VectorToWorldSpace(relativeBounds.Position)
	)
	local targetRadius = supportRadius(target.CFrame, target.Size, away)
	local movingRadius = supportRadius(targetMovingBoundsRotation, moving.Size, away)
	local pivotDistance = targetRadius
		+ movingRadius
		+ desiredGap
		- rotatedOffset:Dot(away)
	local position2 = targetCenter + away * pivotDistance
	local pivotY = moving.Pivot.Position.Y

	return {
		Position = Vector3.new(position2.X, pivotY, position2.Y),
		LookAtPosition = Vector3.new(targetCenter.X, pivotY, targetCenter.Y),
	}
end

return table.freeze(HorizontalBoundsGeometry)
