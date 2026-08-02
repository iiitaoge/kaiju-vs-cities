local BuildingPlacement = require(script.Parent.BuildingPlacement)
local HouseCatalog = require(script.Parent.HouseCatalog)
local InstancePath = require(script.Parent.Parent.InstancePath)

local HouseBoundsResolver = {}

export type HouseTarget = {
	CFrame: CFrame,
	Size: Vector3,
}

function HouseBoundsResolver.Resolve(
	definition: HouseCatalog.HouseDefinition,
	level: number
): HouseTarget
	assert(type(definition) == "table", "definition 必须是 HouseDefinition")
	assert(type(level) == "number" and level > 0, "level 必须大于 0")

	local templatePath = string.format(
		"%s/%s/%s/level%d",
		definition.ModelRoot,
		definition.GroupName,
		definition.VariantName,
		level
	)
	local pointPath = string.format(
		"%s/%s/%s",
		definition.PointRoot,
		definition.GroupName,
		definition.PointName
	)
	local template = InstancePath.Get(templatePath)
	local point = InstancePath.Get(pointPath)
	assert(template:IsA("Model"), string.format("房屋模板不是 Model：%s", templatePath))
	assert(point:IsA("BasePart"), string.format("房屋放置点不是 BasePart：%s", pointPath))

	local boundingCFrame, boundingSize = BuildingPlacement.GetTargetBounds(template, point.CFrame)
	return {
		CFrame = boundingCFrame,
		Size = boundingSize,
	}
end

return HouseBoundsResolver
