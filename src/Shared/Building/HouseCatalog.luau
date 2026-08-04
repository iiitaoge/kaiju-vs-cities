local IncomeZoneConfigs = require(script.Parent.IncomeZoneConfigs)

local HouseCatalog = {}

export type HouseDefinition = {
	HouseId: string,
	RegionId: string,
	ModelRoot: string,
	GroupName: string,
	VariantName: string?,
	BuildAtRegionLevel: number,
	RegionLevelsPerModelLevel: number,
	MaxModelLevel: number?,
}

local definitionsByHouseId: { [string]: HouseDefinition } = {}
local sortedDefinitions: { HouseDefinition } = {}

for regionId, region in pairs(IncomeZoneConfigs) do
	for groupName, houses in pairs(region.Groups) do
		for _, house in ipairs(houses) do
			assert(
				not definitionsByHouseId[house.HouseId],
				string.format("重复的 HouseId：%s", house.HouseId)
			)

			local buildAtRegionLevel = house.BuildAtRegionLevel or 1
			local regionLevelsPerModelLevel = house.RegionLevelsPerModelLevel or 1
			local maxModelLevel = house.MaxModelLevel or region.DefaultMaxModelLevel
			assert(
				type(buildAtRegionLevel) == "number"
					and buildAtRegionLevel >= 1
					and buildAtRegionLevel % 1 == 0,
				house.HouseId .. " BuildAtRegionLevel 无效"
			)
			assert(
				type(regionLevelsPerModelLevel) == "number"
					and regionLevelsPerModelLevel >= 1
					and regionLevelsPerModelLevel % 1 == 0,
				house.HouseId .. " RegionLevelsPerModelLevel 无效"
			)
			assert(
				maxModelLevel == nil
					or (type(maxModelLevel) == "number"
						and maxModelLevel >= 1
						and maxModelLevel % 1 == 0),
				house.HouseId .. " MaxModelLevel 无效"
			)

			definitionsByHouseId[house.HouseId] = {
				HouseId = house.HouseId,
				RegionId = regionId,
				ModelRoot = region.ModelRoot,
				GroupName = groupName,
				VariantName = house.VariantName,
				BuildAtRegionLevel = buildAtRegionLevel,
				RegionLevelsPerModelLevel = regionLevelsPerModelLevel,
				MaxModelLevel = maxModelLevel,
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
