local HouseAttackGeometry = require(script.Parent.HouseAttackGeometry)

local NearbyHouseTargetSelector = {}

local EPSILON = 1e-6

export type HouseCandidate = {
	HouseId: string,
	CFrame: CFrame,
	Size: Vector3,
	HealthGeneration: number,
}

export type SelectOptions = {
	Radius: number,
}

-- 输入：
--   monster：当前正在移动的怪兽模型。
--   candidates：当前 Alive 房屋快照，每项包含 HouseId、CFrame 和 Size。
--   options.Radius：怪兽与房屋水平包围盒之间允许的最大检测距离。
-- 输出：
--   当前半径内边缘距离最近的房屋；没有房屋进入半径时返回 nil。
-- 内部算法：
--   使用双方真实水平包围盒计算边缘距离，重合时距离为 0；
--   只保留距离不大于半径的房屋，再按距离、HouseId 稳定排序。
-- 副作用：无，不移动怪兽、不预约房屋、不修改房屋状态。
function NearbyHouseTargetSelector.Select(
	monster: Model,
	candidates: { HouseCandidate },
	options: SelectOptions
): HouseCandidate?
	assert(monster:IsA("Model"), "monster 必须是 Model")
	assert(type(candidates) == "table", "candidates 必须是 table")
	assert(type(options) == "table", "options 必须是 table")
	assert(
		type(options.Radius) == "number" and options.Radius >= 0,
		"Radius 必须是大于等于 0 的 number"
	)

	local bestCandidate = nil
	local bestGap = math.huge

	for _, candidate in candidates do
		local gap = HouseAttackGeometry.GetGap(monster, candidate)
		if gap > options.Radius + EPSILON then
			continue
		end

		local isBetter = gap < bestGap - EPSILON
			or (
				math.abs(gap - bestGap) <= EPSILON
				and (not bestCandidate or candidate.HouseId < bestCandidate.HouseId)
			)
		if isBetter then
			bestCandidate = candidate
			bestGap = gap
		end
	end

	return bestCandidate
end

return NearbyHouseTargetSelector
