--[[
	职责：把区域等级解析为单栋产钱建筑当前应使用的模型等级。
	输入：区域等级、首次建造等级、每个模型等级占用的区域等级数、可选模型上限。
	输出：尚未建造时返回 nil；已到建造等级时返回正整数模型等级。
	内部算法：按区域等级分段递增模型等级，并在配置上限处封顶。
	不负责：读取配置、修改房屋状态、解析模板、收入、生命或表现。
]]

local IncomeBuildingProgressionRules = {}

local function assertPositiveInteger(value: number, name: string)
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value >= 1
			and value % 1 == 0,
		name .. " 必须是有限正整数"
	)
end

function IncomeBuildingProgressionRules.ResolveModelLevel(
	regionLevel: number,
	buildAtRegionLevel: number,
	regionLevelsPerModelLevel: number,
	maxModelLevel: number?
): number?
	assertPositiveInteger(buildAtRegionLevel, "buildAtRegionLevel")
	assertPositiveInteger(regionLevelsPerModelLevel, "regionLevelsPerModelLevel")
	if maxModelLevel ~= nil then
		assertPositiveInteger(maxModelLevel, "maxModelLevel")
	end
	assert(
		type(regionLevel) == "number"
			and regionLevel == regionLevel
			and regionLevel < math.huge
			and regionLevel >= 0
			and regionLevel % 1 == 0,
		"regionLevel 必须是有限非负整数"
	)

	if regionLevel < buildAtRegionLevel then
		return nil
	end

	local modelLevel = math.floor((regionLevel - 1) / regionLevelsPerModelLevel) + 1
	return if maxModelLevel then math.min(modelLevel, maxModelLevel) else modelLevel
end

return table.freeze(IncomeBuildingProgressionRules)
