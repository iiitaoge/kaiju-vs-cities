--[[
	职责：把怪兽实际等级映射为形态编号、外观等级和稳定 MonsterKey。
	输入：实际等级，以及配置中的每外观等级数、外观数、形态数和 Key 前缀。
	输出：纯数据映射或 nil；不读取实例、不修改玩家状态。
]]

local MonsterLevelProgressionRules = {}

export type Appearance = {
	FormIndex: number,
	VisualLevel: number,
}

local function assertPositiveInteger(value: number, name: string)
	assert(type(value) == "number" and value >= 1 and value % 1 == 0, name .. " 必须是正整数")
end

function MonsterLevelProgressionRules.GetMaxLevel(
	levelsPerAppearance: number,
	visualLevelCount: number,
	formCount: number
): number
	assertPositiveInteger(levelsPerAppearance, "levelsPerAppearance")
	assertPositiveInteger(visualLevelCount, "visualLevelCount")
	assertPositiveInteger(formCount, "formCount")
	return levelsPerAppearance * visualLevelCount * formCount
end

function MonsterLevelProgressionRules.ResolveAppearance(
	level: number,
	levelsPerAppearance: number,
	visualLevelCount: number,
	formCount: number
): Appearance?
	assertPositiveInteger(levelsPerAppearance, "levelsPerAppearance")
	assertPositiveInteger(visualLevelCount, "visualLevelCount")
	assertPositiveInteger(formCount, "formCount")
	if type(level) ~= "number" or level < 1 or level % 1 ~= 0 then
		return nil
	end
	if level > MonsterLevelProgressionRules.GetMaxLevel(levelsPerAppearance, visualLevelCount, formCount) then
		return nil
	end

	local appearanceIndex = math.floor((level - 1) / levelsPerAppearance)
	return {
		FormIndex = math.floor(appearanceIndex / visualLevelCount) + 1,
		VisualLevel = appearanceIndex % visualLevelCount + 1,
	}
end

function MonsterLevelProgressionRules.MakeMonsterKey(prefix: string, level: number): string
	assert(type(prefix) == "string" and prefix ~= "", "prefix 必须是非空字符串")
	assertPositiveInteger(level, "level")
	return string.format("%s%03d", prefix, level)
end

function MonsterLevelProgressionRules.ScaleInteger(baseValue: number, growth: number, level: number): number
	assert(type(baseValue) == "number" and baseValue >= 0 and baseValue < math.huge, "baseValue 无效")
	assert(type(growth) == "number" and growth > 0 and growth < math.huge, "growth 无效")
	assertPositiveInteger(level, "level")
	return math.floor(baseValue * growth ^ (level - 1) + 0.5)
end

return table.freeze(MonsterLevelProgressionRules)
