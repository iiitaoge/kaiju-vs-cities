local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleCatalog = require(ReplicatedStorage.Shared.Vehicle.VehicleCatalog)
local VehicleCrateConfigs = require(ReplicatedStorage.Shared.Vehicle.VehicleCrateConfigs)
local VehicleCrateRules = require(ReplicatedStorage.Shared.Vehicle.VehicleCrateRules)

local VehicleCrateRulesSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "VehicleCrateRulesSpec: " .. message)
end

function VehicleCrateRulesSpec.Run(): boolean
	local definitions = VehicleCatalog.GetAll()
	for _, crate in VehicleCrateConfigs.GetAll() do
		local valid, reason = VehicleCrateRules.Validate(
			crate,
			VehicleCrateConfigs.RarityOrder,
			definitions
		)
		expect(valid, string.format("箱子配置无效：%s", reason or "Unknown"))
		expect(
			VehicleCrateRules.GetDiamondPrice(crate, 1) == crate.DiamondPrice,
			"单抽价格错误"
		)
		expect(VehicleCrateRules.GetDiamondPrice(crate, 5) == nil, "五连抽不得使用钻石价格")
	end

	local wood = VehicleCrateConfigs.Get("Wood")
	expect(wood ~= nil, "Wood 箱子缺失")
	expect(
		VehicleCrateRules.SelectRarity(wood.RarityRates, VehicleCrateConfigs.RarityOrder, 0)
			== "Common",
		"概率起点应落在 Common"
	)
	expect(
		VehicleCrateRules.SelectRarity(wood.RarityRates, VehicleCrateConfigs.RarityOrder, 0.7)
			== "UnCommon",
		"概率边界应进入 UnCommon"
	)
	expect(
		VehicleCrateRules.SelectRarity(wood.RarityRates, VehicleCrateConfigs.RarityOrder, 0.95)
			== "Rare",
		"概率边界应进入 Rare"
	)

	local common = VehicleCrateRules.SelectVehicle(definitions, "Common", 0)
	expect(common and common.VehicleId == "V1", "Common 应映射到 V1")
	local legendary = VehicleCrateRules.SelectVehicle(definitions, "Legendary", 0)
	expect(legendary and legendary.VehicleId == "V5", "Legendary 应映射到 V5")

	local draw, reason = VehicleCrateRules.ResolveDraw(
		wood,
		VehicleCrateConfigs.RarityOrder,
		definitions,
		0,
		0
	)
	expect(draw ~= nil and reason == nil and draw.Vehicle.VehicleId == "V1", "抽取结果错误")
	return true
end

return VehicleCrateRulesSpec
