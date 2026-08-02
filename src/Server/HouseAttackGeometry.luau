local HouseAttackTargetAccess = require(script.Parent.HouseAttackTargetAccess)

local HouseAttackGeometry = {}

local EPSILON = 1e-6

export type AttackPose = {
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

local function supportRadius(cframe: CFrame, size: Vector3, direction: Vector2): number
	local right = unitOrFallback(horizontal(cframe.RightVector), Vector2.new(1, 0))
	local look = unitOrFallback(horizontal(cframe.LookVector), Vector2.new(0, 1))
	return math.abs(direction:Dot(right)) * size.X * 0.5
		+ math.abs(direction:Dot(look)) * size.Z * 0.5
end

-- 输入：
--   monster：需要安排攻击站位的怪兽模型。
--   houseTarget：房屋当前世界包围盒。
--   desiredGap：怪兽与房屋水平包围盒之间期望保留的边缘距离。
-- 输出：
--   Position 是保持怪兽当前 Y 的站位坐标；LookAtPosition 是同高度的房屋朝向点。
-- 副作用：无，不移动或旋转模型。
function HouseAttackGeometry.ResolvePose(
	monster: Model,
	houseTarget: HouseAttackTargetAccess.HouseTarget,
	desiredGap: number
): AttackPose
	assert(monster:IsA("Model"), "monster 必须是 Model")
	assert(type(houseTarget) == "table", "houseTarget 必须是 HouseTarget")
	assert(type(desiredGap) == "number" and desiredGap >= 0, "desiredGap 必须大于等于 0")

	local currentPivot = monster:GetPivot()
	local boundsCFrame, boundsSize = monster:GetBoundingBox()
	local relativeBounds = currentPivot:ToObjectSpace(boundsCFrame)
	local houseCenter = horizontal(houseTarget.CFrame.Position)
	local monsterCenter = horizontal(boundsCFrame.Position)
	local fallbackAway = -horizontal(currentPivot.LookVector)
	local away = unitOrFallback(monsterCenter - houseCenter, fallbackAway)

	local facingRotation = CFrame.lookAt(
		Vector3.zero,
		Vector3.new(-away.X, 0, -away.Y)
	).Rotation
	local targetBoundsRotation = facingRotation * relativeBounds.Rotation
	local rotatedOffset3 = facingRotation:VectorToWorldSpace(relativeBounds.Position)
	local rotatedOffset = horizontal(rotatedOffset3)
	local houseRadius = supportRadius(houseTarget.CFrame, houseTarget.Size, away)
	local monsterRadius = supportRadius(targetBoundsRotation, boundsSize, away)
	local pivotDistance = houseRadius
		+ monsterRadius
		+ desiredGap
		- rotatedOffset:Dot(away)
	local target2 = houseCenter + away * pivotDistance
	local pivotY = currentPivot.Position.Y

	return {
		Position = Vector3.new(target2.X, pivotY, target2.Y),
		LookAtPosition = Vector3.new(houseCenter.X, pivotY, houseCenter.Y),
	}
end

-- 输入：
--   monster：需要检测攻击距离的怪兽模型。
--   houseTarget：房屋最新世界包围盒。
-- 输出：
--   双方水平包围盒沿中心连线方向的边缘间距；重叠时返回 0。
-- 副作用：无。
function HouseAttackGeometry.GetGap(
	monster: Model,
	houseTarget: HouseAttackTargetAccess.HouseTarget
): number
	assert(monster:IsA("Model"), "monster 必须是 Model")
	assert(type(houseTarget) == "table", "houseTarget 必须是 HouseTarget")

	local boundsCFrame, boundsSize = monster:GetBoundingBox()
	local houseCenter = horizontal(houseTarget.CFrame.Position)
	local monsterCenter = horizontal(boundsCFrame.Position)
	local fallbackAway = -horizontal(monster:GetPivot().LookVector)
	local away = unitOrFallback(monsterCenter - houseCenter, fallbackAway)
	local centerDistance = (monsterCenter - houseCenter).Magnitude
	local houseRadius = supportRadius(houseTarget.CFrame, houseTarget.Size, away)
	local monsterRadius = supportRadius(boundsCFrame, boundsSize, away)

	return math.max(0, centerDistance - houseRadius - monsterRadius)
end

return HouseAttackGeometry
