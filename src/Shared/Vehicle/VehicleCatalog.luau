--[[
	职责：保存所有载具类型的稳定身份、模板路径和战斗/奖励属性。
	输入：vehicleId。
	输出：对应的只读载具定义；GetAll 返回全部定义。
	内部算法：以 VehicleId 建立索引，不创建模型、不保存玩家拥有关系。
	不负责：载具实例、派遣、Nest 占用、战斗或奖励结算。
]]

local VehicleCatalog = {}

export type VehicleDefinition = {
	VehicleId: string,
	Name: string,
	Rarity: string,
	TemplatePath: string,
	MaxHealth: number,
	Attack: number,
	DiamondMultiplier: number,
}

local definitions: { VehicleDefinition } = table.freeze({
	table.freeze({
		VehicleId = "V1",
		Name = "Emerald_Command",
		Rarity = "Common",
		TemplatePath = "ReplicatedStorage/Assets/Vehicle/V1",
		MaxHealth = 100,
		Attack = 10,
		DiamondMultiplier = 1,
	}),
	table.freeze({
		VehicleId = "V2",
		Name = "Sandstorm_Patrol",
		Rarity = "UnCommon",
		TemplatePath = "ReplicatedStorage/Assets/Vehicle/V2",
		MaxHealth = 130,
		Attack = 13,
		DiamondMultiplier = 1.2,
	}),
	table.freeze({
		VehicleId = "V3",
		Name = "Frost_Missile",
		Rarity = "Rare",
		TemplatePath = "ReplicatedStorage/Assets/Vehicle/V3",
		MaxHealth = 170,
		Attack = 17,
		DiamondMultiplier = 1.45,
	}),
	table.freeze({
		VehicleId = "V4",
		Name = "Emerald_Siege",
		Rarity = "Epic",
		TemplatePath = "ReplicatedStorage/Assets/Vehicle/V4",
		MaxHealth = 220,
		Attack = 22,
		DiamondMultiplier = 1.75,
	}),
	table.freeze({
		VehicleId = "V5",
		Name = "Azure_Plasma",
		Rarity = "Legendary",
		TemplatePath = "ReplicatedStorage/Assets/Vehicle/V5",
		MaxHealth = 280,
		Attack = 28,
		DiamondMultiplier = 2.1,
	}),
})

local byId = {}
for _, definition in definitions do
	byId[definition.VehicleId] = definition
end
table.freeze(byId)

function VehicleCatalog.Get(vehicleId: string): VehicleDefinition?
	if type(vehicleId) ~= "string" then
		return nil
	end
	return byId[vehicleId]
end

function VehicleCatalog.GetAll(): { VehicleDefinition }
	return definitions
end

return table.freeze({
	UnlockRegionId = "R3",
	DefaultVehicleId = "V1",
	MaxDeployedVehicles = 3,
	TemplateRootPath = "ReplicatedStorage/Assets/Vehicle",
	Get = VehicleCatalog.Get,
	GetAll = VehicleCatalog.GetAll,
})
