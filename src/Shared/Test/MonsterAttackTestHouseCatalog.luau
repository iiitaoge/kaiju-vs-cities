local BuildingPlacement = require(script.Parent.Parent.Building.BuildingPlacement)
local InstancePath = require(script.Parent.Parent.InstancePath)
local MonsterAttackTestConfig = require(script.Parent.MonsterAttackTestConfig)

local MonsterAttackTestHouseCatalog = {}

export type HouseDefinition = {
	HouseId: string,
	Point: BasePart,
	Template: Model,
	-- LocalModelBuilder 的输入；已自动把模板水平包围盒底部对齐放置点。
	PlacementCFrame: CFrame,
	-- 房屋放置后的真实世界包围盒。
	CFrame: CFrame,
	Size: Vector3,
}

local definitions: { HouseDefinition }? = nil
local definitionsById: { [string]: HouseDefinition }? = nil

local function load()
	if definitions and definitionsById then
		return
	end

	local template = InstancePath.Get(MonsterAttackTestConfig.Paths.HouseTemplate)
	local pointsRoot = InstancePath.Get(MonsterAttackTestConfig.Paths.HousePoints)
	assert(template:IsA("Model"), "测试房屋模板必须是 Model")

	local points = {}
	for _, child in pointsRoot:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(points, child)
		end
	end
	table.sort(points, function(a, b)
		return a.Name < b.Name
	end)

	local loadedDefinitions = {}
	local loadedById = {}
	for _, point in points do
		local rawBoundsCFrame, size = BuildingPlacement.GetTargetBounds(template, point.CFrame)
		local rawBottom = rawBoundsCFrame.Position.Y - size.Y * 0.5
		local verticalOffset = point.Position.Y - rawBottom
		local placementCFrame = point.CFrame + Vector3.new(0, verticalOffset, 0)
		local boundsCFrame = rawBoundsCFrame + Vector3.new(0, verticalOffset, 0)
		local houseId = MonsterAttackTestConfig.HouseIdPrefix .. point.Name

		assert(not loadedById[houseId], string.format("重复的测试 HouseId：%s", houseId))
		local definition = {
			HouseId = houseId,
			Point = point,
			Template = template,
			PlacementCFrame = placementCFrame,
			CFrame = boundsCFrame,
			Size = size,
		}
		table.insert(loadedDefinitions, definition)
		loadedById[houseId] = definition
	end

	assert(#loadedDefinitions > 0, "测试房屋放置点不能为空")
	definitions = loadedDefinitions
	definitionsById = loadedById
end

-- 输入：无。
-- 输出：按放置点名称升序排列的测试房屋定义新数组。
-- 副作用：首次调用时读取 Studio 测试模板与放置点，并缓存其放置范围。
function MonsterAttackTestHouseCatalog.GetAll(): { HouseDefinition }
	load()
	return table.clone(definitions :: { HouseDefinition })
end

-- 输入：稳定测试 houseId。
-- 输出：对应的测试房屋定义；不存在时返回 nil。
-- 副作用：首次调用时会加载测试目录。
function MonsterAttackTestHouseCatalog.Get(houseId: string): HouseDefinition?
	load()
	return (definitionsById :: { [string]: HouseDefinition })[houseId]
end

return MonsterAttackTestHouseCatalog
