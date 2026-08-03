local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HorizontalBoundsGeometry = require(
	ReplicatedStorage.Shared.Geometry.HorizontalBoundsGeometry
)

local HouseAttackGeometry = {}

export type HouseTarget = {
	CFrame: CFrame,
	Size: Vector3,
}

export type AttackPose = HorizontalBoundsGeometry.Pose

-- 输入：
--   monster：需要安排攻击站位的怪兽模型。
--   houseTarget：房屋当前世界包围盒。
--   desiredGap：怪兽与房屋水平包围盒之间期望保留的边缘距离。
-- 输出：
--   Position 是保持怪兽当前 Y 的站位坐标；LookAtPosition 是同高度的房屋朝向点。
-- 副作用：无，不移动或旋转模型。
function HouseAttackGeometry.ResolvePose(
	monster: Model,
	houseTarget: HouseTarget,
	desiredGap: number
): AttackPose
	assert(monster:IsA("Model"), "monster 必须是 Model")
	assert(type(houseTarget) == "table", "houseTarget 必须是 HouseTarget")
	assert(type(desiredGap) == "number" and desiredGap >= 0, "desiredGap 必须大于等于 0")

	local pivot = monster:GetPivot()
	local boundsCFrame, boundsSize = monster:GetBoundingBox()
	return HorizontalBoundsGeometry.ResolvePose({
		Pivot = pivot,
		CFrame = boundsCFrame,
		Size = boundsSize,
	}, {
		CFrame = houseTarget.CFrame,
		Size = houseTarget.Size,
	}, desiredGap)
end

-- 输入：
--   monster：需要检测攻击距离的怪兽模型。
--   houseTarget：房屋最新世界包围盒。
-- 输出：
--   双方水平包围盒沿中心连线方向的边缘间距；重叠时返回 0。
-- 副作用：无。
function HouseAttackGeometry.GetGap(
	monster: Model,
	houseTarget: HouseTarget
): number
	assert(monster:IsA("Model"), "monster 必须是 Model")
	assert(type(houseTarget) == "table", "houseTarget 必须是 HouseTarget")

	local boundsCFrame, boundsSize = monster:GetBoundingBox()
	return HorizontalBoundsGeometry.GetGap({
		CFrame = houseTarget.CFrame,
		Size = houseTarget.Size,
	}, {
		CFrame = boundsCFrame,
		Size = boundsSize,
	}, -monster:GetPivot().LookVector)
end

return HouseAttackGeometry
