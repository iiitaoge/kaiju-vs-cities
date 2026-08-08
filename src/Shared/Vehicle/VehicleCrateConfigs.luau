--[[
	职责：保存载具箱子的稳定 ID、图标名称、钻石价格和稀有度概率。
	输入：调用方按 CrateId 读取配置。
	输出：箱子配置列表，以及用于 DropRates 展示的稀有度顺序。
	内部算法：纯配置索引，不执行随机、不扣货币、不创建载具。
	不负责：抽取、拥有关系、部署、Robux 收据或 UI。

	当前价格和概率是可调的初始配置。RobuxProductId 等待商品 ID 确定后再填写。
]]

local rarityOrder = table.freeze({
	"Common",
	"UnCommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythical",
})

local function freezeRates(rates)
	return table.freeze(rates)
end

local crates = table.freeze({
	table.freeze({
		CrateId = "Wood",
		Name = "Wood",
		IconName = "box1",
		DiamondPrice = 100,
		FiveDrawDiamondPrice = 450,
		RobuxProductId = 0,
		RarityRates = freezeRates({
			Common = 70,
			UnCommon = 25,
			Rare = 5,
			Epic = 0,
			Legendary = 0,
			Mythical = 0,
		}),
	}),
	table.freeze({
		CrateId = "Iron",
		Name = "Iron",
		IconName = "box2",
		DiamondPrice = 250,
		FiveDrawDiamondPrice = 1_100,
		RobuxProductId = 0,
		RarityRates = freezeRates({
			Common = 40,
			UnCommon = 35,
			Rare = 20,
			Epic = 5,
			Legendary = 0,
			Mythical = 0,
		}),
	}),
	table.freeze({
		CrateId = "Gold",
		Name = "Gold",
		IconName = "box3",
		DiamondPrice = 600,
		FiveDrawDiamondPrice = 2_700,
		RobuxProductId = 0,
		RarityRates = freezeRates({
			Common = 15,
			UnCommon = 30,
			Rare = 30,
			Epic = 20,
			Legendary = 5,
			Mythical = 0,
		}),
	}),
	table.freeze({
		CrateId = "Mythic",
		Name = "Mythic",
		IconName = "box4",
		DiamondPrice = 1_500,
		FiveDrawDiamondPrice = 6_750,
		RobuxProductId = 0,
		RarityRates = freezeRates({
			Common = 5,
			UnCommon = 10,
			Rare = 20,
			Epic = 35,
			Legendary = 30,
			Mythical = 0,
		}),
	}),
})

local byId = {}
for _, crate in crates do
	byId[crate.CrateId] = crate
end
table.freeze(byId)

local VehicleCrateConfigs = {}

function VehicleCrateConfigs.Get(crateId: string)
	if type(crateId) ~= "string" then
		return nil
	end
	return byId[crateId]
end

function VehicleCrateConfigs.GetAll()
	return crates
end

return table.freeze({
	RarityOrder = rarityOrder,
	Get = VehicleCrateConfigs.Get,
	GetAll = VehicleCrateConfigs.GetAll,
})
