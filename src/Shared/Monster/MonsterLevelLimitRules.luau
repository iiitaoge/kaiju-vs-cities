--[[
	职责：根据重生次数计算怪兽当前可用的最高等级。
	输入：非负整数 RebirthCount、每个形态的等级数、形态总数。
	输出：当前重生阶段允许的最高等级；最高不超过成长线总等级。
	内部算法：初始可用 1 个形态，每次重生再解锁 1 个形态，最后按总形态数封顶。
	不负责：读取玩家状态、读取配置、判断资格、升级或修改存档。
]]

local MonsterLevelLimitRules = {}

local function assertPositiveInteger(value: number, name: string)
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value >= 1
			and value % 1 == 0,
			name .. " 必须是正整数"
	)
end

local function assertRebirthCount(value: number)
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value >= 0
			and value % 1 == 0,
			"rebirthCount 必须是有限非负整数"
	)
end

function MonsterLevelLimitRules.ResolveMaxLevel(
	rebirthCount: number,
	levelsPerForm: number,
	formCount: number
): number
	assertRebirthCount(rebirthCount)
	assertPositiveInteger(levelsPerForm, "levelsPerForm")
	assertPositiveInteger(formCount, "formCount")

	local unlockedFormCount = math.min(rebirthCount + 1, formCount)
	return levelsPerForm * unlockedFormCount
end

function MonsterLevelLimitRules.CheckTargetLevel(
	targetLevel: number,
	currentMaxLevel: number,
	totalMaxLevel: number
): (boolean, string?)
	assertPositiveInteger(targetLevel, "targetLevel")
	assertPositiveInteger(currentMaxLevel, "currentMaxLevel")
	assertPositiveInteger(totalMaxLevel, "totalMaxLevel")
	assert(currentMaxLevel <= totalMaxLevel, "currentMaxLevel 不得超过 totalMaxLevel")

	if targetLevel > totalMaxLevel then
		return false, "MaxLevel"
	end
	if targetLevel > currentMaxLevel then
		return false, "RebirthRequired"
	end
	return true, nil
end

return table.freeze(MonsterLevelLimitRules)
