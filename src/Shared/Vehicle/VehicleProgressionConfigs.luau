--[[
	职责：配置载具 1 到 20 级的成长倍率、升级金币和销毁钻石报酬。
	输入：level，以及可选的 vehicleId。
	输出：等级配置，或合并基础载具属性后的最终属性。
	内部算法：等级表提供成长因子；最终生命、攻击和钻石倍率由 VehicleCatalog
	的基础属性乘以对应等级因子并统一取整。
	不负责：玩家拥有关系、货币扣除、存档、派遣或 UI。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleCatalog = require(ReplicatedStorage.Shared.Vehicle.VehicleCatalog)

local VehicleProgressionConfigs = {}

export type LevelDefinition = {
	Level: number,
	MaxHealthMultiplier: number,
	AttackMultiplier: number,
	DiamondMultiplier: number,
	UpgradeCost: number,
	DestroyReward: number,
}

-- UpgradeCost 是“从当前等级升到下一级”的金币消耗；20 级没有下一级。
local levels: { LevelDefinition } = table.freeze({
	table.freeze({ Level = 1, MaxHealthMultiplier = 1.00, AttackMultiplier = 1.00, DiamondMultiplier = 1.00, UpgradeCost = 1_000, DestroyReward = 10 }),
	table.freeze({ Level = 2, MaxHealthMultiplier = 1.12, AttackMultiplier = 1.10, DiamondMultiplier = 1.05, UpgradeCost = 2_500, DestroyReward = 12 }),
	table.freeze({ Level = 3, MaxHealthMultiplier = 1.25, AttackMultiplier = 1.22, DiamondMultiplier = 1.10, UpgradeCost = 5_000, DestroyReward = 14 }),
	table.freeze({ Level = 4, MaxHealthMultiplier = 1.39, AttackMultiplier = 1.35, DiamondMultiplier = 1.15, UpgradeCost = 9_000, DestroyReward = 16 }),
	table.freeze({ Level = 5, MaxHealthMultiplier = 1.54, AttackMultiplier = 1.50, DiamondMultiplier = 1.20, UpgradeCost = 15_000, DestroyReward = 18 }),
	table.freeze({ Level = 6, MaxHealthMultiplier = 1.70, AttackMultiplier = 1.66, DiamondMultiplier = 1.25, UpgradeCost = 24_000, DestroyReward = 20 }),
	table.freeze({ Level = 7, MaxHealthMultiplier = 1.87, AttackMultiplier = 1.83, DiamondMultiplier = 1.30, UpgradeCost = 36_000, DestroyReward = 23 }),
	table.freeze({ Level = 8, MaxHealthMultiplier = 2.05, AttackMultiplier = 2.02, DiamondMultiplier = 1.35, UpgradeCost = 52_000, DestroyReward = 26 }),
	table.freeze({ Level = 9, MaxHealthMultiplier = 2.24, AttackMultiplier = 2.22, DiamondMultiplier = 1.40, UpgradeCost = 72_000, DestroyReward = 30 }),
	table.freeze({ Level = 10, MaxHealthMultiplier = 2.44, AttackMultiplier = 2.43, DiamondMultiplier = 1.45, UpgradeCost = 96_000, DestroyReward = 34 }),
	table.freeze({ Level = 11, MaxHealthMultiplier = 2.65, AttackMultiplier = 2.65, DiamondMultiplier = 1.50, UpgradeCost = 125_000, DestroyReward = 38 }),
	table.freeze({ Level = 12, MaxHealthMultiplier = 2.87, AttackMultiplier = 2.88, DiamondMultiplier = 1.55, UpgradeCost = 160_000, DestroyReward = 42 }),
	table.freeze({ Level = 13, MaxHealthMultiplier = 3.10, AttackMultiplier = 3.12, DiamondMultiplier = 1.60, UpgradeCost = 200_000, DestroyReward = 46 }),
	table.freeze({ Level = 14, MaxHealthMultiplier = 3.34, AttackMultiplier = 3.37, DiamondMultiplier = 1.65, UpgradeCost = 250_000, DestroyReward = 50 }),
	table.freeze({ Level = 15, MaxHealthMultiplier = 3.59, AttackMultiplier = 3.63, DiamondMultiplier = 1.70, UpgradeCost = 310_000, DestroyReward = 55 }),
	table.freeze({ Level = 16, MaxHealthMultiplier = 3.85, AttackMultiplier = 3.90, DiamondMultiplier = 1.75, UpgradeCost = 380_000, DestroyReward = 60 }),
	table.freeze({ Level = 17, MaxHealthMultiplier = 4.12, AttackMultiplier = 4.18, DiamondMultiplier = 1.80, UpgradeCost = 460_000, DestroyReward = 65 }),
	table.freeze({ Level = 18, MaxHealthMultiplier = 4.40, AttackMultiplier = 4.47, DiamondMultiplier = 1.85, UpgradeCost = 550_000, DestroyReward = 70 }),
	table.freeze({ Level = 19, MaxHealthMultiplier = 4.69, AttackMultiplier = 4.77, DiamondMultiplier = 1.90, UpgradeCost = 650_000, DestroyReward = 75 }),
	table.freeze({ Level = 20, MaxHealthMultiplier = 5.00, AttackMultiplier = 5.10, DiamondMultiplier = 2.00, UpgradeCost = 0, DestroyReward = 80 }),
})

local byLevel: { [number]: LevelDefinition } = {}
for _, definition in levels do
	byLevel[definition.Level] = definition
end
table.freeze(byLevel)

function VehicleProgressionConfigs.Get(level: number): LevelDefinition?
	if type(level) ~= "number" or level % 1 ~= 0 then
		return nil
	end
	return byLevel[level]
end

function VehicleProgressionConfigs.GetForVehicle(
	vehicleId: string,
	level: number
)
	local vehicle = VehicleCatalog.Get(vehicleId)
	local progression = VehicleProgressionConfigs.Get(level)
	if not vehicle or not progression then
		return nil
	end
	return {
		VehicleId = vehicle.VehicleId,
		Name = vehicle.Name,
		Level = progression.Level,
		MaxHealth = math.max(1, math.floor(vehicle.MaxHealth * progression.MaxHealthMultiplier + 0.5)),
		Attack = math.max(1, math.floor(vehicle.Attack * progression.AttackMultiplier + 0.5)),
		DiamondMultiplier = vehicle.DiamondMultiplier * progression.DiamondMultiplier,
		UpgradeCost = progression.UpgradeCost,
		DestroyReward = progression.DestroyReward,
	}
end

function VehicleProgressionConfigs.GetAll(): { LevelDefinition }
	return levels
end

return table.freeze({
	MaxLevel = #levels,
	Get = VehicleProgressionConfigs.Get,
	GetForVehicle = VehicleProgressionConfigs.GetForVehicle,
	GetAll = VehicleProgressionConfigs.GetAll,
})
