local HorizontalBoundsGeometry = require(
	script.Parent.Parent.Geometry.HorizontalBoundsGeometry
)

local MonsterCombatGeometry = {}

export type AttackPose = HorizontalBoundsGeometry.Pose

-- 输入：两个怪兽模型。
-- 输出：双方水平包围盒之间的边缘距离；重叠时为零。
-- 内部算法：沿双方中心连线计算两个有向包围盒的支撑半径。
function MonsterCombatGeometry.GetGap(attacker: Model, target: Model): number
	assert(attacker:IsA("Model"), "attacker 必须是 Model")
	assert(target:IsA("Model"), "target 必须是 Model")

	local attackerCFrame, attackerSize = attacker:GetBoundingBox()
	local targetCFrame, targetSize = target:GetBoundingBox()
	return HorizontalBoundsGeometry.GetGap({
		CFrame = attackerCFrame,
		Size = attackerSize,
	}, {
		CFrame = targetCFrame,
		Size = targetSize,
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

	local pivot = attacker:GetPivot()
	local attackerBounds, attackerSize = attacker:GetBoundingBox()
	local targetBounds, targetSize = target:GetBoundingBox()
	return HorizontalBoundsGeometry.ResolvePose({
		Pivot = pivot,
		CFrame = attackerBounds,
		Size = attackerSize,
	}, {
		CFrame = targetBounds,
		Size = targetSize,
	}, desiredGap)
end

return MonsterCombatGeometry
