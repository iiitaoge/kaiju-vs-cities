local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaidProductCatalog = require(ReplicatedStorage.Shared.Monetization.PaidProductCatalog)
local VehicleCrateConfigs = require(ReplicatedStorage.Shared.Vehicle.VehicleCrateConfigs)

local PaidProductCatalogSpec = {}

function PaidProductCatalogSpec.Run(): boolean
	for _, product in PaidProductCatalog.GetConfigured() do
		assert(product.ProductId > 0, "商品目录不得注册占位 ProductId")
		assert(PaidProductCatalog.Get(product.ProductId) == product, "商品索引不一致")
	end
	local monsterProductId = PaidProductCatalog.GetMonsterUpgradeToMaxProductId()
	if monsterProductId == 0 then
		assert(PaidProductCatalog.Get(monsterProductId) == nil, "0 占位不应进入商品索引")
	else
		local monsterProduct = PaidProductCatalog.Get(monsterProductId)
		assert(
			monsterProduct ~= nil and monsterProduct.Kind == "MonsterUpgradeToMax",
			"怪兽商品索引错误"
		)
	end
	for _, crate in VehicleCrateConfigs.GetAll() do
		assert(
			PaidProductCatalog.GetVehicleProductId(crate.CrateId, 1)
				== crate.RobuxSingleProductId,
			"单抽商品配置映射错误"
		)
		assert(
			PaidProductCatalog.GetVehicleProductId(crate.CrateId, 5)
				== crate.RobuxFiveDrawProductId,
			"五连抽商品配置映射错误"
		)
	end
	return true
end

return PaidProductCatalogSpec
