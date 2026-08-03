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
	- R3 使用第三组城市模板的首版占位数值。
	- R4、R5 使用快速跑通建造链路的测试数值。
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
		BaseIncome = 50,
		IncomeGrowth = 1.6,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 100,
		CostGrowth = 1.6,
	},

	R2 = {
		UnlockCost = 100,
		PurchaseCost = 200,
		BaseIncome = 500,
		IncomeGrowth = 1.6,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 1000,
		CostGrowth = 1.6,
	},

	R3 = {
		UnlockCost = 500,
		PurchaseCost = 1000,
		BaseIncome = 2500,
		IncomeGrowth = 1.6,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 5000,
		CostGrowth = 1.6,
	},

	R4 = {
		UnlockCost = 0,
		PurchaseCost = 0,
		BaseIncome = 10000,
		IncomeGrowth = 1.5,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 100,
		CostGrowth = 1.25,
	},

	R5 = {
		UnlockCost = 0,
		PurchaseCost = 0,
		BaseIncome = 100000,
		IncomeGrowth = 2,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 10,
		CostGrowth = 1.2,
	},
}

for _, config in pairs(configs) do
	table.freeze(config)
end

return table.freeze(configs)
