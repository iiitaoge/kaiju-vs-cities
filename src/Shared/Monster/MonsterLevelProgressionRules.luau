--[[
	职责：把怪兽实际等级映射为形态编号、形态内等级、成长进度和稳定 MonsterKey。
	输入：实际等级，以及配置中的每形态等级数、形态数和 Key 前缀。
	输出：纯数据映射或 nil；不读取实例、不修改玩家状态。
]]

local MonsterLevelProgressionRules = {}

export type Appearance = {
	FormIndex: number,
	FormLevel: number,
	GrowthAlpha: number,
}

local function assertPositiveInteger(value: number, name: string)
	assert(type(value) == "number" and value >= 1 and value % 1 == 0, name .. " 必须是正整数")
end

function MonsterLevelProgressionRules.GetMaxLevel(
	levelsPerForm: number,
	formCount: number
): number
	assertPositiveInteger(levelsPerForm, "levelsPerForm")
	assertPositiveInteger(formCount, "formCount")
	return levelsPerForm * formCount
end

function MonsterLevelProgressionRules.ResolveAppearance(
	level: number,
	levelsPerForm: number,
	formCount: number
): Appearance?
	assertPositiveInteger(levelsPerForm, "levelsPerForm")
	assertPositiveInteger(formCount, "formCount")
	if type(level) ~= "number" or level < 1 or level % 1 ~= 0 then
		return nil
	end
	if level > MonsterLevelProgressionRules.GetMaxLevel(levelsPerForm, formCount) then
		return nil
	end

	local zeroBasedLevel = level - 1
	local formLevel = zeroBasedLevel % levelsPerForm + 1
	return {
		FormIndex = math.floor(zeroBasedLevel / levelsPerForm) + 1,
		FormLevel = formLevel,
		GrowthAlpha = if levelsPerForm == 1
			then 1
			else (formLevel - 1) / (levelsPerForm - 1),
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

-- 输入：基础值、按等级上限排列的成长阶段，以及实际等级。
-- 输出：跨阶段连续成长并四舍五入后的整数；Level 1 返回基础值。
-- 阶段示例：{ { UntilLevel = 30, Growth = 1.4 }, { UntilLevel = 75, Growth = 1.15 } }。
function MonsterLevelProgressionRules.ScaleIntegerByStages(
	baseValue: number,
	stages,
	level: number
): number
	assert(type(baseValue) == "number" and baseValue >= 0 and baseValue < math.huge, "baseValue 无效")
	assert(type(stages) == "table" and #stages >= 1, "stages 必须是非空数组")
	assertPositiveInteger(level, "level")

	local value = baseValue
	local previousUntilLevel = 1
	for index, stage in ipairs(stages) do
		assert(type(stage) == "table", string.format("stages[%d] 必须是 table", index))
		assertPositiveInteger(stage.UntilLevel, string.format("stages[%d].UntilLevel", index))
		assert(
			stage.UntilLevel > previousUntilLevel,
			string.format("stages[%d].UntilLevel 必须递增", index)
		)
		assert(
			type(stage.Growth) == "number"
				and stage.Growth > 0
				and stage.Growth < math.huge,
			string.format("stages[%d].Growth 无效", index)
		)

		local appliedUntilLevel = math.min(level, stage.UntilLevel)
		local stepCount = math.max(0, appliedUntilLevel - previousUntilLevel)
		value *= stage.Growth ^ stepCount
		previousUntilLevel = stage.UntilLevel
		if level <= stage.UntilLevel then
			return math.floor(value + 0.5)
		end
	end

	error(string.format("等级 %d 超出成长阶段配置", level))
end

return table.freeze(MonsterLevelProgressionRules)
