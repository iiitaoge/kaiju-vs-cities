local HorizontalBoundsGeometry = require(
	script.Parent.Parent.Geometry.HorizontalBoundsGeometry
)

local MonsterCombatGeometry = {}

export type AttackPose = HorizontalBoundsGeometry.Pose

local function modelBounds(model: Model): HorizontalBoundsGeometry.MovingBounds
	local pivot = model:GetPivot()
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	return {
		Pivot = pivot,
		CFrame = boundsCFrame,
		Size = boundsSize,
	}
end

-- 输入：两个怪兽模型。
-- 输出：双方水平包围盒之间的边缘距离；重叠时为零。
-- 内部算法：沿双方中心连线计算两个有向包围盒的支撑半径。
function MonsterCombatGeometry.GetGap(attacker: Model, target: Model): number
	assert(attacker:IsA("Model"), "attacker 必须是 Model")
	assert(target:IsA("Model"), "target 必须是 Model")

	local attackerBounds = modelBounds(attacker)
	local targetBounds = modelBounds(target)
	return HorizontalBoundsGeometry.GetGap({
		CFrame = attackerBounds.CFrame,
		Size = attackerBounds.Size,
	}, {
		CFrame = targetBounds.CFrame,
		Size = targetBounds.Size,
	}, attacker:GetPivot().LookVector)
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

	local attackerBounds = modelBounds(attacker)
	local targetBoundsCFrame, targetBoundsSize = target:GetBoundingBox()
	return HorizontalBoundsGeometry.ResolvePose({
		Pivot = attackerBounds.Pivot,
		CFrame = attackerBounds.CFrame,
		Size = attackerBounds.Size,
	}, {
		CFrame = targetBoundsCFrame,
		Size = targetBoundsSize,
	}, desiredGap)
end

-- 输入：移动怪兽、固定目标点、期望边缘间距和移动怪兽所在一侧的离开方向。
-- 输出：按真实包围盒/Pivot 偏移计算的精确站位与朝向点。
-- 内部算法：把目标点作为零尺寸包围盒，复用统一的有向包围盒站位算法。
function MonsterCombatGeometry.ResolvePoseToPoint(
	monster: Model,
	targetCFrame: CFrame,
	desiredGap: number,
	awayDirection: Vector3
): AttackPose
	assert(monster:IsA("Model"), "monster 必须是 Model")
	assert(typeof(targetCFrame) == "CFrame", "targetCFrame 必须是 CFrame")
	assert(type(desiredGap) == "number" and desiredGap >= 0, "desiredGap 无效")
	assert(typeof(awayDirection) == "Vector3", "awayDirection 必须是 Vector3")

	local bounds = modelBounds(monster)
	return HorizontalBoundsGeometry.ResolvePoseWithAway(
		bounds,
		{
			CFrame = targetCFrame,
			Size = Vector3.zero,
		},
		desiredGap,
		Vector2.new(awayDirection.X, awayDirection.Z)
	)
end

return MonsterCombatGeometry
