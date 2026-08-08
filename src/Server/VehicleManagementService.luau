--[[
	职责：提供载具列表、升级和销毁的服务器管理入口。
	输入：RemoteFunction 接收 GetState、Upgrade、Destroy；后两者接收车辆实例 ID。
	输出：服务端计算的车辆状态、升级后的等级或销毁发放的钻石报酬。
	内部算法：Ready 校验 → 校验玩家拥有且未派遣 → 读取等级配置 → 扣金币/发钻石
	并修改 Fleet → 排入立即存档。
	不负责：Nest 派遣、战斗、模型生成、区域占领或 UI。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiamondService = require(script.Parent.DiamondService)
local MoneyService = require(script.Parent.MoneyService)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerPersistenceCoordinator = require(script.Parent.PlayerPersistenceCoordinator)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local VehicleFleetService = require(script.Parent.VehicleFleetService)
local VehicleRuntimeService = require(script.Parent.VehicleRuntimeService)
local ZoneStateService = require(script.Parent.ZoneStateService)
local VehicleCatalog = require(ReplicatedStorage.Shared.Vehicle.VehicleCatalog)
local VehicleManagementProtocol = require(
	ReplicatedStorage.Shared.Vehicle.VehicleManagementProtocol
)
local VehicleProgressionConfigs = require(
	ReplicatedStorage.Shared.Vehicle.VehicleProgressionConfigs
)

local VehicleManagementService = {}

local actionBusy: { [Player]: boolean } = setmetatable({}, { __mode = "k" })
local started = false

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function isReady(player: Player): (boolean, string?)
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status == "Unmanaged" then
		return true, nil
	end
	if readiness.Status ~= "Ready" or not readiness.CanSave then
		return false, "PlayerDataNotReady"
	end
	return true, nil
end

local function isFeatureUnlocked(player: Player): boolean
	return ZoneStateService.GetUnlocked(player, VehicleCatalog.UnlockRegionId)
end

local function serializeVehicle(vehicle)
	local progression = VehicleProgressionConfigs.GetForVehicle(
		vehicle.VehicleId,
		vehicle.Level
	)
	if not progression then
		return nil
	end
	return {
		InstanceId = vehicle.InstanceId,
		VehicleId = vehicle.VehicleId,
		Name = progression.Name,
		Level = progression.Level,
		MaxHealth = progression.MaxHealth,
		Attack = progression.Attack,
		DiamondMultiplier = progression.DiamondMultiplier,
		UpgradeCost = progression.UpgradeCost,
		DestroyReward = progression.DestroyReward,
		Active = vehicle.Active,
	}
end

local function getState(player: Player)
	local vehicles = {}
	local deployedCount = 0
	for _, vehicle in VehicleFleetService.List(player) do
		local serialized = serializeVehicle(vehicle)
		if serialized then
			table.insert(vehicles, serialized)
			if vehicle.Active then
				deployedCount += 1
			end
		end
	end
	table.sort(vehicles, function(a, b)
		return a.InstanceId < b.InstanceId
	end)
	return {
		Vehicles = vehicles,
		DeployedCount = deployedCount,
		MaxDeployedVehicles = VehicleCatalog.MaxDeployedVehicles,
		MaxLevel = VehicleProgressionConfigs.MaxLevel,
	}
end

local function response(player: Player, succeeded: boolean, reason: string?)
	return {
		Succeeded = succeeded,
		Reason = reason,
		State = getState(player),
		Balances = {
			Money = MoneyService.Get(player),
			Diamond = DiamondService.Get(player),
		},
	}
end

local function lockedResponse(player: Player)
	return {
		Succeeded = false,
		Reason = "R3Locked",
		State = nil,
		Balances = {
			Money = MoneyService.Get(player),
			Diamond = DiamondService.Get(player),
		},
	}
end

local function queueSave(player: Player)
	local queued, reason = PlayerPersistenceCoordinator.SavePlayer(player)
	if not queued then
		warn(string.format(
			"载具管理变更已应用但立即存档未入队：%s (%s)",
			player.Name,
			tostring(reason)
		))
	end
end

local function upgrade(player: Player, instanceId: string)
	local vehicle = VehicleFleetService.Get(player, instanceId)
	if not vehicle then
		return response(player, false, "VehicleNotOwned")
	end
	if vehicle.Active then
		return response(player, false, "VehicleDeployed")
	end

	local current = VehicleProgressionConfigs.GetForVehicle(
		vehicle.VehicleId,
		vehicle.Level
	)
	if not current then
		return response(player, false, "UnknownVehicleLevel")
	end
	if vehicle.Level >= VehicleProgressionConfigs.MaxLevel then
		return response(player, false, "MaxLevel")
	end

	local nextLevel = vehicle.Level + 1
	local nextDefinition = VehicleProgressionConfigs.GetForVehicle(
		vehicle.VehicleId,
		nextLevel
	)
	if not nextDefinition then
		return response(player, false, "UnknownVehicleLevel")
	end

	local spent = MoneyService.TrySpend(player, current.UpgradeCost)
	if not spent.Succeeded then
		return response(player, false, spent.Reason or "InsufficientFunds")
	end

	local changed, changeReason = VehicleFleetService.SetLevel(
		player,
		instanceId,
		nextLevel
	)
	if not changed then
		MoneyService.Add(player, current.UpgradeCost)
		return response(player, false, changeReason or "UpgradeFailed")
	end

	queueSave(player)
	local result = response(player, true, nil)
	result.Vehicle = serializeVehicle(vehicle)
	return result
end

local function destroy(player: Player, instanceId: string)
	local vehicle = VehicleFleetService.Get(player, instanceId)
	if not vehicle then
		return response(player, false, "VehicleNotOwned")
	end
	if vehicle.Active then
		return response(player, false, "VehicleDeployed")
	end

	local definition = VehicleProgressionConfigs.GetForVehicle(
		vehicle.VehicleId,
		vehicle.Level
	)
	if not definition then
		return response(player, false, "UnknownVehicleLevel")
	end

	local removed, removeReason = VehicleFleetService.Remove(player, instanceId)
	if not removed then
		return response(player, false, removeReason or "DestroyFailed")
	end

	local despawned, despawnReason = VehicleRuntimeService.DespawnInstance(player, instanceId)
	if not despawned then
		warn(string.format(
			"载具已销毁但运行时模型清理失败：%s (%s)",
			instanceId,
			despawnReason or "Unknown"
		))
	end
	DiamondService.Add(player, definition.DestroyReward)
	queueSave(player)
	local result = response(player, true, nil)
	result.DestroyedInstanceId = instanceId
	result.DiamondReward = definition.DestroyReward
	return result
end

local function onRequest(player: Player, requestKind, instanceId)
	assertPlayer(player)
	local ready, readyReason = isReady(player)
	if not ready then
		return {
			Succeeded = false,
			Reason = readyReason,
			State = nil,
			Balances = nil,
		}
	end
	if not isFeatureUnlocked(player) then
		return lockedResponse(player)
	end

	if requestKind == VehicleManagementProtocol.RequestKinds.GetState then
		return response(player, true, nil)
	end
	if requestKind ~= VehicleManagementProtocol.RequestKinds.Upgrade
		and requestKind ~= VehicleManagementProtocol.RequestKinds.Destroy
	then
		return response(player, false, "InvalidRequestKind")
	end
	if type(instanceId) ~= "string" or instanceId == "" then
		return response(player, false, "InvalidVehicleInstanceId")
	end
	if actionBusy[player] then
		return response(player, false, "ActionBusy")
	end
	actionBusy[player] = true

	local succeeded, resultOrError = xpcall(function()
		if requestKind == VehicleManagementProtocol.RequestKinds.Upgrade then
			return upgrade(player, instanceId)
		end
		return destroy(player, instanceId)
	end, debug.traceback)
	actionBusy[player] = nil
	if not succeeded then
		warn(string.format("载具管理请求异常：%s/%s (%s)", player.Name, tostring(requestKind), tostring(resultOrError)))
		return response(player, false, "ServerError")
	end
	return resultOrError
end

function VehicleManagementService.Start()
	if started then
		return
	end
	started = true

	local remote = ServerRemoteAccess.EnsureFunction(VehicleManagementProtocol.RemoteName)
	remote.OnServerInvoke = onRequest
	Players.PlayerRemoving:Connect(function(player)
		actionBusy[player] = nil
	end)
end

return VehicleManagementService
