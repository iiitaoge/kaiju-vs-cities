--[[
	职责：
	- 保存区域经济测试数值。

	输入：
	- 无。

	输出：
	- 以 RegionId 为键的只读约定配置表。

	读取模块：
	- EconomyMath
	- HouseIncomeService
	- RegionStateService
	- RegionUpgradeService

	写入模块：
	- 无。运行时模块不得修改本配置。

	字段：
	- UnlockCost：Locked -> Unlocked 的现金成本。
	- PurchaseCost：已解锁区域从 Level 0 -> Level 1 的现金成本。
	- BaseIncome：Level 1 时，区域全部已建造房屋在一个收入周期内的总收入。
	- IncomeGrowth：区域总收入每级的指数增长倍率。
	- IncomeIntervalSeconds：BaseIncome 对应的收入周期秒数。
	- UpgradeBaseCost：区域从 Level 1 -> Level 2 的现金成本。
	- CostGrowth：后续升级成本每级的指数增长倍率。

	测试映射：
	- R1 模仿住宅区。
	- R2 模仿市中心。
]]

export type RegionEconomyConfig = {
	UnlockCost: number,
	PurchaseCost: number,
	BaseIncome: number,
	IncomeGrowth: number,
	IncomeIntervalSeconds: number,
	UpgradeBaseCost: number,
	CostGrowth: number,
}

local configs: { [string]: RegionEconomyConfig } = {
	R1 = {
		UnlockCost = 0,
		PurchaseCost = 0,
		BaseIncome = 2,
		IncomeGrowth = 1.6,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 100,
		CostGrowth = 1.6,
	},

	R2 = {
		UnlockCost = 3500,
		PurchaseCost = 7000,
		BaseIncome = 200,
		IncomeGrowth = 1.6,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 40000,
		CostGrowth = 1.6,
	},
}

for _, config in pairs(configs) do
	table.freeze(config)
end

return table.freeze(configs)
