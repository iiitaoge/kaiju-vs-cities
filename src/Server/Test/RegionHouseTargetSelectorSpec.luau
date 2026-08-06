local RegionHouseTargetSelector = require(script.Parent.Parent.RegionHouseTargetSelector)

local RegionHouseTargetSelectorSpec = {}

local function candidate(houseId: string, regionId: string, x: number)
	return {
		HouseId = houseId,
		RegionId = regionId,
		CFrame = CFrame.new(x, 0, 0),
	}
end

function RegionHouseTargetSelectorSpec.Run(): boolean
	local candidates = {
		candidate("OtherRegion", "R2", 1),
		candidate("B", "R1", 5),
		candidate("A", "R1", -5),
		candidate("Far", "R1", 20),
	}
	local first = RegionHouseTargetSelector.Select(Vector3.zero, "R1", candidates)
	assert(first and first.HouseId == "A", "必须过滤区域并按 HouseId 稳定处理等距")

	local second = RegionHouseTargetSelector.Select(
		Vector3.zero,
		"R1",
		candidates,
		{ A = true }
	)
	assert(second and second.HouseId == "B", "忽略已处理房屋后应选择下一栋")
	assert(
		RegionHouseTargetSelector.Select(Vector3.zero, "R3", candidates) == nil,
		"目标区域没有房屋时必须返回 nil"
	)
	return true
end

return RegionHouseTargetSelectorSpec
