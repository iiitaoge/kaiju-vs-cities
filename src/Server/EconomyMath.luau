--[[
	职责：
	- 提供区域经济的纯数值计算。

	输入：
	- RegionEconomyConfigs 中的单区域配置。
	- 区域等级、收入倍率、已建造房屋数量和时间。

	输出：
	- 区域收入、单栋房屋收入、累计收入或升级成本。

	读取：
	- 只读取调用方传入的数据。

	写入：
	- 无。

	不负责：
	- 不读取玩家状态。
	- 不修改余额、区域或房屋状态。
]]

local RegionEconomyConfigs = require(script.Parent.RegionEconomyConfigs)

type RegionEconomyConfig = RegionEconomyConfigs.RegionEconomyConfig

local EconomyMath = {}

local function assertFiniteNonNegative(value: number, name: string)
	assert(type(value) == "number", string.format("%s 必须是 number", name))
	assert(value == value and value < math.huge and value >= 0, string.format("%s 必须是有限非负数", name))
end

local function assertPositive(value: number, name: string)
	assertFiniteNonNegative(value, name)
	assert(value > 0, string.format("%s 必须大于 0", name))
end

-- 输入：区域配置、当前区域等级、最终收入倍率。
-- 输出：区域全部已建造房屋在当前等级下的每秒总收入；Level 0 返回 0。
function EconomyMath.GetRegionIncomePerSecond(
	config: RegionEconomyConfig,
	level: number,
	multiplier: number
): number
	assert(type(config) == "table", "config 必须是 table")
	assertFiniteNonNegative(level, "level")
	assertFiniteNonNegative(multiplier, "multiplier")
	assertPositive(config.IncomeIntervalSeconds, "IncomeIntervalSeconds")

	level = math.floor(level)
	if level <= 0 then
		return 0
	end

	return config.BaseIncome
		* config.IncomeGrowth ^ (level - 1)
		* multiplier
		/ config.IncomeIntervalSeconds
end

-- 输入：区域每秒总收入、当前已建造房屋数量（Alive + Destroyed + Rebuilding）。
-- 输出：一栋已建造房屋的每秒名义收入；没有已建造房屋时返回 0。
function EconomyMath.GetHouseIncomePerSecond(
	regionIncomePerSecond: number,
	builtHouseCount: number
): number
	assertFiniteNonNegative(regionIncomePerSecond, "regionIncomePerSecond")
	assertFiniteNonNegative(builtHouseCount, "builtHouseCount")

	builtHouseCount = math.floor(builtHouseCount)
	if builtHouseCount <= 0 then
		return 0
	end

	return regionIncomePerSecond / builtHouseCount
end

-- 输入：单栋每秒收入、上次结算时间、当前结算时间。
-- 输出：这段时间新增的收入；时间倒退时按 0 处理。
function EconomyMath.GetAccumulatedIncome(
	incomePerSecond: number,
	lastIncomeAt: number,
	now: number
): number
	assertFiniteNonNegative(incomePerSecond, "incomePerSecond")
	assertFiniteNonNegative(lastIncomeAt, "lastIncomeAt")
	assertFiniteNonNegative(now, "now")

	return incomePerSecond * math.max(0, now - lastIncomeAt)
end

-- 输入：区域配置、当前区域等级。
-- 输出：Level 0 -> 1 使用 PurchaseCost；Level N -> N+1 使用指数升级成本。
function EconomyMath.GetUpgradeCost(config: RegionEconomyConfig, currentLevel: number): number
	assert(type(config) == "table", "config 必须是 table")
	assertFiniteNonNegative(currentLevel, "currentLevel")

	currentLevel = math.floor(currentLevel)
	if currentLevel <= 0 then
		return config.PurchaseCost
	end

	return config.UpgradeBaseCost * config.CostGrowth ^ (currentLevel - 1)
end

return EconomyMath
