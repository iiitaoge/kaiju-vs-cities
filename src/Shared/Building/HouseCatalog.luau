local Regions = require(script.Parent.Regions)

local HouseCatalog = {}

export type HouseDefinition = {
	HouseId: string,
	RegionId: string,
	ModelRoot: string,
	PointRoot: string,
	GroupName: string,
	VariantName: string,
	PointName: string,
}

local definitionsByHouseId: { [string]: HouseDefinition } = {}
local sortedDefinitions: { HouseDefinition } = {}

for regionId, region in pairs(Regions) do
	for groupName, houses in pairs(region.Groups) do
		for _, house in ipairs(houses) do
			assert(
				not definitionsByHouseId[house.HouseId],
				string.format("重复的 HouseId：%s", house.HouseId)
			)

			definitionsByHouseId[house.HouseId] = {
				HouseId = house.HouseId,
				RegionId = regionId,
				ModelRoot = region.ModelRoot,
				PointRoot = region.PointRoot,
				GroupName = groupName,
				VariantName = house.VariantName,
				PointName = house.PointName,
			}
		end
	end
end

for _, definition in pairs(definitionsByHouseId) do
	table.insert(sortedDefinitions, definition)
end

table.sort(sortedDefinitions, function(a, b)
	return a.HouseId < b.HouseId
end)

function HouseCatalog.Get(houseId: string): HouseDefinition?
	return definitionsByHouseId[houseId]
end

-- 输入：无。
-- 输出：按 HouseId 升序排列的房屋定义新数组；调用者修改数组不会影响目录内部顺序。
function HouseCatalog.GetAll(): { HouseDefinition }
	return table.clone(sortedDefinitions)
end

return HouseCatalog
