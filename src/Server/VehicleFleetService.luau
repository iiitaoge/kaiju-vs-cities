--[[
	职责：维护在线玩家拥有的全部载具实例；部署数量限制由派遣服务负责。
	输入：Register 接收 Player 和 VehicleId；Get/List/SetActive 接收玩家和实例 ID。
	输出：载具实例记录、注册结果和当前拥有列表。
	内部算法：按玩家弱键保存实例表；VehicleId 表示类型，InstanceId 表示玩家实际拥有的一台车。
	不负责：模型、派遣、Nest 占用、战斗、奖励或存档。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleCatalog = require(ReplicatedStorage.Shared.Vehicle.VehicleCatalog)
local VehicleProgressionConfigs = require(
	ReplicatedStorage.Shared.Vehicle.VehicleProgressionConfigs
)
local ZoneStateService = require(script.Parent.ZoneStateService)

local VehicleFleetService = {}

export type VehicleInstance = {
	InstanceId: string,
	VehicleId: string,
	Level: number,
	OwnerUserId: number,
	Active: boolean,
}

export type RegisterResult = {
	Succeeded: boolean,
	Reason: string?,
	Vehicle: VehicleInstance?,
}

type FleetState = {
	Vehicles: { [string]: VehicleInstance },
	NextSerial: number,
}

local fleets: { [Player]: FleetState } = setmetatable({}, { __mode = "k" })

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function getFleet(player: Player): FleetState
	local fleet = fleets[player]
	if not fleet then
		fleet = {
			Vehicles = {},
			NextSerial = 1,
		}
		fleets[player] = fleet
	end
	return fleet
end

function VehicleFleetService.Register(player: Player, vehicleId: string): RegisterResult
	assertPlayer(player)
	assert(type(vehicleId) == "string" and vehicleId ~= "", "vehicleId 必须是非空字符串")
	if player.Parent ~= Players then
		return { Succeeded = false, Reason = "PlayerUnavailable", Vehicle = nil }
	end
	if not ZoneStateService.GetUnlocked(player, VehicleCatalog.UnlockRegionId) then
		return { Succeeded = false, Reason = "R3Locked", Vehicle = nil }
	end

	local definition = VehicleCatalog.Get(vehicleId)
	if not definition then
		return { Succeeded = false, Reason = "UnknownVehicle", Vehicle = nil }
	end

	local fleet = getFleet(player)
	local instanceId = string.format("Vehicle%d", fleet.NextSerial)
	fleet.NextSerial += 1
	local vehicle: VehicleInstance = {
		InstanceId = instanceId,
		VehicleId = definition.VehicleId,
		Level = 1,
		OwnerUserId = player.UserId,
		Active = false,
	}
	fleet.Vehicles[instanceId] = vehicle
	return { Succeeded = true, Reason = nil, Vehicle = vehicle }
end

function VehicleFleetService.Restore(player: Player, savedVehicles)
	assertPlayer(player)

	local fleet: FleetState = {
		Vehicles = {},
		NextSerial = 1,
	}
	-- Fleet 是玩家资产。恢复资产不依赖 R3 当前运行时状态；R3 只负责
	-- 载具功能入口，避免区域状态异常时把已保存车辆静默丢弃。
	if type(savedVehicles) ~= "table" then
		fleets[player] = fleet
		return 0
	end

	for instanceId, saved in savedVehicles do
		if type(instanceId) ~= "string"
			or instanceId == ""
			or string.find(instanceId, "[/\\\\]") ~= nil
			or type(saved) ~= "table"
		then
			continue
		end

		local definition = VehicleCatalog.Get(saved.VehicleId)
		local level = saved.Level
		if definition
			and type(level) == "number"
			and level % 1 == 0
			and VehicleProgressionConfigs.Get(level)
		then
			local vehicle: VehicleInstance = {
				InstanceId = instanceId,
				VehicleId = definition.VehicleId,
				Level = level,
				OwnerUserId = player.UserId,
				Active = false,
			}
			fleet.Vehicles[instanceId] = vehicle

			local serial = string.match(instanceId, "^Vehicle(%d+)$")
			if serial then
				fleet.NextSerial = math.max(fleet.NextSerial, tonumber(serial) + 1)
			end
		end
	end

	fleets[player] = fleet
	local restoredCount = 0
	for _ in fleet.Vehicles do
		restoredCount += 1
	end
	return restoredCount
end

function VehicleFleetService.Capture(player: Player)
	assertPlayer(player)
	local captured = {}
	local fleet = fleets[player]
	if not fleet then
		return captured
	end
	for instanceId, vehicle in fleet.Vehicles do
		captured[instanceId] = {
			VehicleId = vehicle.VehicleId,
			Level = vehicle.Level,
		}
	end
	return captured
end

function VehicleFleetService.Get(player: Player, instanceId: string): VehicleInstance?
	assertPlayer(player)
	assert(type(instanceId) == "string" and instanceId ~= "", "instanceId 必须是非空字符串")
	local fleet = fleets[player]
	return if fleet then fleet.Vehicles[instanceId] else nil
end

function VehicleFleetService.List(player: Player): { VehicleInstance }
	assertPlayer(player)
	local fleet = fleets[player]
	local result = {}
	if fleet then
		for _, vehicle in fleet.Vehicles do
			table.insert(result, vehicle)
		end
	end
	table.sort(result, function(a, b)
		return a.InstanceId < b.InstanceId
	end)
	return result
end

function VehicleFleetService.SetActive(
	player: Player,
	instanceId: string,
	active: boolean
): (boolean, string?)
	local vehicle = VehicleFleetService.Get(player, instanceId)
	if not vehicle then
		return false, "VehicleNotOwned"
	end
	vehicle.Active = active
	return true, nil
end

function VehicleFleetService.SetLevel(
	player: Player,
	instanceId: string,
	level: number
): (boolean, string?)
	local vehicle = VehicleFleetService.Get(player, instanceId)
	if not vehicle then
		return false, "VehicleNotOwned"
	end
	if vehicle.Active then
		return false, "VehicleActive"
	end
	if not VehicleProgressionConfigs.Get(level) then
		return false, "InvalidVehicleLevel"
	end
	vehicle.Level = level
	return true, nil
end

function VehicleFleetService.Remove(player: Player, instanceId: string): (boolean, string?)
	local vehicle = VehicleFleetService.Get(player, instanceId)
	if not vehicle then
		return false, "VehicleNotOwned"
	end
	if vehicle.Active then
		return false, "VehicleActive"
	end
	local fleet = fleets[player]
	assert(fleet, "载具 Fleet 状态丢失")
	local vehicleCount = 0
	for _ in fleet.Vehicles do
		vehicleCount += 1
	end
	if vehicleCount <= 1 then
		return false, "CannotDestroyLastVehicle"
	end
	fleet.Vehicles[instanceId] = nil
	return true, nil
end

function VehicleFleetService.Clear(player: Player)
	assertPlayer(player)
	fleets[player] = nil
end

return VehicleFleetService
