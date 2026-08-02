local MonsterCombatGeometry = {}

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

-- 输入：两个怪兽模型。
-- 输出：双方水平包围盒之间的边缘距离；重叠时为零。
-- 内部算法：沿双方中心连线计算两个有向包围盒的支撑半径。
function MonsterCombatGeometry.GetGap(attacker: Model, target: Model): number
	assert(attacker:IsA("Model"), "attacker 必须是 Model")
	assert(target:IsA("Model"), "target 必须是 Model")

	local attackerCFrame, attackerSize = attacker:GetBoundingBox()
	local targetCFrame, targetSize = target:GetBoundingBox()
	local attackerCenter = horizontal(attackerCFrame.Position)
	local targetCenter = horizontal(targetCFrame.Position)
	local fallback = horizontal(attacker:GetPivot().LookVector)
	local direction = unitOrFallback(targetCenter - attackerCenter, fallback)
	local centerDistance = (targetCenter - attackerCenter).Magnitude
	local attackerRadius = supportRadius(attackerCFrame, attackerSize, direction)
	local targetRadius = supportRadius(targetCFrame, targetSize, direction)
	return math.max(0, centerDistance - attackerRadius - targetRadius)
end

-- 输入：准备靠近的怪兽、目标怪兽和期望边缘距离。
-- 输出：保持攻击者当前 Y 的攻击站位和朝向点。
-- 内部算法：根据双方真实水平包围盒计算攻击者 Pivot 的目标位置。
function MonsterCombatGeometry.ResolvePose(
	attacker: Model,
	target: Model,
	desiredGap: number
): AttackPose
	assert(attacker:IsA("Model"), "attacker 必须是 Model")
	assert(target:IsA("Model"), "target 必须是 Model")
	assert(type(desiredGap) == "number" and desiredGap >= 0, "desiredGap 无效")

	local attackerPivot = attacker:GetPivot()
	local attackerBounds, attackerSize = attacker:GetBoundingBox()
	local targetBounds, targetSize = target:GetBoundingBox()
	local targetCenter = horizontal(targetBounds.Position)
	local attackerCenter = horizontal(attackerBounds.Position)
	local away = unitOrFallback(
		attackerCenter - targetCenter,
		-horizontal(attackerPivot.LookVector)
	)
	local relativeBounds = attackerPivot:ToObjectSpace(attackerBounds)
	local facingRotation = CFrame.lookAt(
		Vector3.zero,
		Vector3.new(-away.X, 0, -away.Y)
	).Rotation
	local targetAttackerBoundsRotation = facingRotation * relativeBounds.Rotation
	local rotatedOffset = horizontal(facingRotation:VectorToWorldSpace(relativeBounds.Position))
	local targetRadius = supportRadius(targetBounds, targetSize, away)
	local attackerRadius = supportRadius(targetAttackerBoundsRotation, attackerSize, away)
	local pivotDistance = targetRadius + attackerRadius + desiredGap - rotatedOffset:Dot(away)
	local position2 = targetCenter + away * pivotDistance
	local y = attackerPivot.Position.Y

	return {
		Position = Vector3.new(position2.X, y, position2.Y),
		LookAtPosition = Vector3.new(targetCenter.X, y, targetCenter.Y),
	}
end

return MonsterCombatGeometry
