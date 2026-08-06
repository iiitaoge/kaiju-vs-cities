--[[
	职责：从指定区域的存活房屋快照中选择最靠近玩家落点的一栋。
	输入：落点、区域 ID、房屋快照，以及可选忽略集合。
	输出：最近候选；等距时按 HouseId 稳定选择；没有候选时返回 nil。
	不负责：读取场景、距离限制、移动、预约、伤害或动画。
]]

local RegionHouseTargetSelector = {}

local EPSILON = 1e-6

export type Candidate = {
	HouseId: string,
	RegionId: string,
	CFrame: CFrame,
}

function RegionHouseTargetSelector.Select(
	origin: Vector3,
	regionId: string,
	candidates: { Candidate },
	ignoredHouseIds: { [string]: boolean }?
): Candidate?
	assert(typeof(origin) == "Vector3", "origin 必须是 Vector3")
	assert(type(regionId) == "string" and regionId ~= "", "regionId 必须是非空字符串")
	assert(type(candidates) == "table", "candidates 必须是 table")
	assert(
		ignoredHouseIds == nil or type(ignoredHouseIds) == "table",
		"ignoredHouseIds 必须是 table 或 nil"
	)

	local best: Candidate? = nil
	local bestDistance = math.huge
	local origin2D = Vector2.new(origin.X, origin.Z)
	for _, candidate in candidates do
		if candidate.RegionId ~= regionId
			or (ignoredHouseIds and ignoredHouseIds[candidate.HouseId]) then
			continue
		end
		local position = candidate.CFrame.Position
		local distance = (Vector2.new(position.X, position.Z) - origin2D).Magnitude
		local better = distance < bestDistance - EPSILON
			or (
				math.abs(distance - bestDistance) <= EPSILON
				and (best == nil or candidate.HouseId < best.HouseId)
			)
		if better then
			best = candidate
			bestDistance = distance
		end
	end
	return best
end

return RegionHouseTargetSelector
