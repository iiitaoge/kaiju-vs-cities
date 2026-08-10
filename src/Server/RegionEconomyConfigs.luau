--[[
	职责：
	- 保存 R1～R6 的 30 级正式首版经济曲线。

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

	节奏约定：
	- 玩家将新区升到约 Level 5 后进入下一地区。
	- 按主成长路线购买 Boost、怪兽与支线内容时，R6 约在 30 分钟建成。
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
		BaseIncome = 60,
		IncomeGrowth = 1.20,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 50,
		CostGrowth = 1.45,
	},

	R2 = {
		UnlockCost = 0,
		PurchaseCost = 3_000,
		BaseIncome = 650,
		IncomeGrowth = 1.18,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 1_200,
		CostGrowth = 1.45,
	},

	R3 = {
		UnlockCost = 300_000,
		PurchaseCost = 150_000,
		BaseIncome = 2_000,
		IncomeGrowth = 1.18,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 60_000,
		CostGrowth = 1.45,
	},

	R4 = {
		UnlockCost = 1_000_000,
		PurchaseCost = 500_000,
		BaseIncome = 25_000,
		IncomeGrowth = 1.15,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 600_000,
		CostGrowth = 1.45,
	},

	R5 = {
		UnlockCost = 12_000_000,
		PurchaseCost = 12_000_000,
		BaseIncome = 150_000,
		IncomeGrowth = 1.12,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 4_000_000,
		CostGrowth = 1.45,
	},

	R6 = {
		UnlockCost = 75_000_000,
		PurchaseCost = 75_000_000,
		BaseIncome = 900_000,
		IncomeGrowth = 1.12,
		IncomeIntervalSeconds = 1,
		UpgradeBaseCost = 25_000_000,
		CostGrowth = 1.45,
	},
}

for _, config in pairs(configs) do
	table.freeze(config)
end

return table.freeze(configs)
