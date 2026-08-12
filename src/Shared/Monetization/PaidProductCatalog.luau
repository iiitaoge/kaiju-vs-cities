--[[
	职责：把固定 Developer Product ID 映射为服务器可识别的权益定义。
	输入：ProductId，或 CrateId + 抽取次数。
	输出：不可变的 MonsterUpgradeToMax / VehicleCrate 商品定义。
	内部算法：启动时建立唯一正数 ProductId 索引；0 只表示占位，不进入商品索引。
	不负责：收据幂等、购买提示、随机抽取、怪兽升级或存档。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaidProductConfigs = require(script.Parent.PaidProductConfigs)
local VehicleCrateConfigs = require(
	ReplicatedStorage.Shared.Vehicle.VehicleCrateConfigs
)

local PaidProductCatalog = {}

export type ProductDefinition = {
	ProductId: number,
	Kind: "MonsterUpgradeToMax" | "VehicleCrate",
	CrateId: string?,
	DrawCount: number?,
	TargetLevel: ("Max" | number)?,
}

local byProductId: { [number]: ProductDefinition } = {}
local configured = {}

local function register(definition: ProductDefinition)
	local productId = definition.ProductId
	if productId == 0 then
		return
	end
	assert(
		type(productId) == "number"
			and productId > 0
			and productId % 1 == 0,
		"Developer ProductId 必须是正整数或 0 占位"
	)
	assert(byProductId[productId] == nil, "Developer ProductId 重复配置：" .. tostring(productId))
	byProductId[productId] = table.freeze(definition)
	table.insert(configured, byProductId[productId])
end

register({
	ProductId = PaidProductConfigs.MonsterUpgradeToMaxProductId,
	Kind = "MonsterUpgradeToMax",
	TargetLevel = PaidProductConfigs.MonsterUpgradeTargetLevel,
})

for _, crate in VehicleCrateConfigs.GetAll() do
	register({
		ProductId = crate.RobuxSingleProductId,
		Kind = "VehicleCrate",
		CrateId = crate.CrateId,
		DrawCount = 1,
	})
	register({
		ProductId = crate.RobuxFiveDrawProductId,
		Kind = "VehicleCrate",
		CrateId = crate.CrateId,
		DrawCount = 5,
	})
end

table.freeze(configured)
table.freeze(byProductId)

function PaidProductCatalog.Get(productId: number): ProductDefinition?
	if type(productId) ~= "number" or productId % 1 ~= 0 then
		return nil
	end
	return byProductId[productId]
end

function PaidProductCatalog.GetMonsterUpgradeToMaxProductId(): number
	return PaidProductConfigs.MonsterUpgradeToMaxProductId
end

function PaidProductCatalog.GetMonsterUpgradeTargetLevel(): ("Max" | number)
	return PaidProductConfigs.MonsterUpgradeTargetLevel
end

function PaidProductCatalog.GetVehicleProductId(crateId: string, drawCount: number): number
	local crate = VehicleCrateConfigs.Get(crateId)
	if not crate then
		return 0
	end
	if drawCount == 1 then
		return crate.RobuxSingleProductId
	end
	if drawCount == 5 then
		return crate.RobuxFiveDrawProductId
	end
	return 0
end

function PaidProductCatalog.GetConfigured(): { ProductDefinition }
	return table.clone(configured)
end

return table.freeze(PaidProductCatalog)
