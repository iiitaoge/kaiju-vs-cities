--[[
	职责：在 R3 已解锁时，把玩家的 Jeep 放入其 Plot 的运行时车辆目录。

	输入：Spawn 接收在线 Player；Start 注册玩家加载后的恢复流程。
	输出：Spawn 返回 Succeeded、Reason 和当前 Jeep Model。
	内部算法：读取玩家已分配 Plot → 校验 R3/Vehiclespawn 与 Jeep 模板 →
	在 Plot/Runtime/Vehicles 下复用已有 Jeep 或 Clone 后按出生点 CFrame 放置。

	不负责：R3 解锁、玩家存档、车辆驾驶或探险逻辑。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local ZoneStateService = require(script.Parent.ZoneStateService)

local JeepRuntimeService = {}

export type SpawnResult = {
	Succeeded: boolean,
	Reason: string?,
	Model: Model?,
}

local REGION_ID = "R3"
local VEHICLE_NAME = "jeep"
local VEHICLES_ROOT_NAME = "Vehicles"
local VEHICLE_TEMPLATE_PATH = "ReplicatedStorage/Assets/Vehicle/jeep"
local VEHICLE_SPAWN_NAME = "Vehiclespawn"

local started = false

local function result(succeeded: boolean, reason: string?, model: Model?): SpawnResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		Model = model,
	}
end

local function getTemplate(): (Model?, string?)
	local template = InstancePath.Find(VEHICLE_TEMPLATE_PATH)
	if not template then
		return nil, "JeepTemplateUnavailable"
	end
	if not template:IsA("Model") then
		return nil, "JeepTemplateInvalid"
	end
	return template, nil
end

local function getSpawnPoint(plot: Model): (BasePart?, string?)
	local zones = plot:FindFirstChild("Zones")
	local region = zones and zones:FindFirstChild(REGION_ID)
	if not region then
		return nil, "R3ZoneUnavailable"
	end

	local spawnPoint = region:FindFirstChild(VEHICLE_SPAWN_NAME)
	if not spawnPoint then
		return nil, "JeepSpawnPointUnavailable"
	end
	if not spawnPoint:IsA("BasePart") then
		return nil, "JeepSpawnPointInvalid"
	end
	return spawnPoint, nil
end

local function getOrCreateVehiclesRoot(plot: Model): (Folder?, string?)
	local runtime = plot:FindFirstChild("Runtime")
	if not runtime or not runtime:IsA("Folder") then
		return nil, "MissingPlotRuntime"
	end

	local existing = runtime:FindFirstChild(VEHICLES_ROOT_NAME)
	if existing then
		if not existing:IsA("Folder") then
			return nil, "InvalidVehiclesRuntime"
		end
		return existing, nil
	end

	local vehicles = Instance.new("Folder")
	vehicles.Name = VEHICLES_ROOT_NAME
	vehicles.Parent = runtime
	return vehicles, nil
end

local function createJeep(
	player: Player,
	template: Model,
	targetCFrame: CFrame,
	vehicles: Folder
): Model
	local jeep = template:Clone()
	jeep.Name = VEHICLE_NAME
	jeep:SetAttribute("VehicleOwnerUserId", player.UserId)
	jeep:SetAttribute("VehicleId", VEHICLE_NAME)
	jeep:PivotTo(targetCFrame)
	jeep.Parent = vehicles
	return jeep
end

function JeepRuntimeService.Spawn(player: Player): SpawnResult
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	if player.Parent ~= Players then
		return result(false, "PlayerUnavailable", nil)
	end
	if not ZoneStateService.GetUnlocked(player, REGION_ID) then
		return result(false, "R3Locked", nil)
	end

	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return result(false, plotReason or "PlayerHasNoPlot", nil)
	end

	local spawnPoint, spawnPointReason = getSpawnPoint(plot)
	if not spawnPoint then
		return result(false, spawnPointReason or "JeepSpawnPointUnavailable", nil)
	end

	local template, templateReason = getTemplate()
	if not template then
		return result(false, templateReason or "JeepTemplateUnavailable", nil)
	end

	local vehicles, runtimeReason = getOrCreateVehiclesRoot(plot)
	if not vehicles then
		return result(false, runtimeReason or "InvalidVehiclesRuntime", nil)
	end

	local existing = vehicles:FindFirstChild(VEHICLE_NAME)
	if existing then
		if not existing:IsA("Model") then
			return result(false, "InvalidJeepRuntime", nil)
		end
		existing:SetAttribute("VehicleOwnerUserId", player.UserId)
		existing:SetAttribute("VehicleId", VEHICLE_NAME)
		existing:PivotTo(spawnPoint.CFrame)
		return result(true, nil, existing)
	end

	return result(true, nil, createJeep(player, template, spawnPoint.CFrame, vehicles))
end

local function restoreWhenReady(player: Player)
	local ready = PlayerDataReadyService.Wait(player)
	if not ready or player.Parent ~= Players then
		return
	end
	if not ZoneStateService.GetUnlocked(player, REGION_ID) then
		return
	end

	local spawned = JeepRuntimeService.Spawn(player)
	if not spawned.Succeeded then
		warn(string.format(
			"恢复 Jeep 失败：%s (%s)",
			player.Name,
			spawned.Reason or "Unknown"
		))
	end
end

function JeepRuntimeService.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(function(player)
		task.defer(restoreWhenReady, player)
	end)
	for _, player in Players:GetPlayers() do
		task.defer(restoreWhenReady, player)
	end
end

return JeepRuntimeService
