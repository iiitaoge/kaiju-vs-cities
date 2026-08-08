--[[
	职责：创建和移动玩家载具的运行时 Model。
	输入：Spawn 接收 Player、vehicleInstanceId、vehicleId 和可选的等级生命值；
		StartNestTravel/StartNestOrbit 接收 Model、Nest Model 和 NestId。
	输出：Spawn 返回 Model 与派遣前 HomeCFrame；载具从出生点行驶到 Nest 半径后持续绕圈。
	内部算法：读取 VehicleCatalog 模板 → 找到玩家 Plot 的待命点 → 在 Plot/Runtime/Vehicles
	下按实例 ID 复用或 Clone；运动由 Heartbeat 驱动，车辆出生高度作为巢穴运动高度基准，
	行驶和绕圈时使用 FrontMarker 的视觉方向水平朝向巢穴中心，半径和角度修正来自 NestOrbitConfigs。
	不负责：载具拥有关系、派遣、Nest 占用、战斗、奖励或存档。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local NestOrbitConfigs = require(ReplicatedStorage.Shared.Nest.NestOrbitConfigs)
local VehicleCatalog = require(ReplicatedStorage.Shared.Vehicle.VehicleCatalog)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)

local VehicleRuntimeService = {}

export type SpawnResult = {
	Succeeded: boolean,
	Reason: string?,
	Model: Model?,
	HomeCFrame: CFrame?,
}

local VEHICLES_ROOT_NAME = "Vehicles"
local VEHICLE_HOME_SPAWN_NAME = "Vehiclespawn"

type Motion = {
	Active: boolean,
	Connection: RBXScriptConnection?,
}

local activeMotions: { [Model]: Motion } = setmetatable({}, { __mode = "k" })

local function result(
	succeeded: boolean,
	reason: string?,
	model: Model?,
	homeCFrame: CFrame?
): SpawnResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		Model = model,
		HomeCFrame = homeCFrame,
	}
end

local function assertIdentifier(value: string, name: string)
	assert(type(value) == "string" and value ~= "", name .. " 必须是非空字符串")
	assert(string.find(value, "[/\\]") == nil, name .. " 不能包含路径分隔符")
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

local function findSpawnPointIn(container: Instance): BasePart?
	local child = container:FindFirstChild(VEHICLE_HOME_SPAWN_NAME)
	return if child and child:IsA("BasePart") then child else nil
end

local function getHomeCFrame(plot: Model): (CFrame?, string?)
	local direct = findSpawnPointIn(plot)
	if direct then
		return direct.CFrame, nil
	end

	local zones = plot:FindFirstChild("Zones")
	if zones then
		-- 兼容现有场景的 Zones/R3/Vehiclespawn，但不再依赖 R3 解锁状态。
		local preferredRegion = zones:FindFirstChild("R3")
		local preferred = preferredRegion and findSpawnPointIn(preferredRegion)
		if preferred then
			return preferred.CFrame, nil
		end
		for _, region in zones:GetChildren() do
			local spawnPoint = findSpawnPointIn(region)
			if spawnPoint then
				return spawnPoint.CFrame, nil
			end
		end
	end

	local origin = plot:FindFirstChild("Origin")
	if origin and origin:IsA("BasePart") then
		return origin.CFrame, nil
	end
	return nil, "VehicleHomeSpawnUnavailable"
end

local function getTemplate(vehicleId: string): (Model?, string?)
	local definition = VehicleCatalog.Get(vehicleId)
	if not definition then
		return nil, "UnknownVehicle"
	end
	local template = InstancePath.Find(definition.TemplatePath)
	if not template then
		return nil, "VehicleTemplateUnavailable"
	end
	if not template:IsA("Model") then
		return nil, "VehicleTemplateInvalid"
	end
	return template, nil
end

local function applyIdentity(
	model: Model,
	player: Player,
	vehicleInstanceId: string,
	vehicleId: string,
	state: string,
	maxHealth: number,
	health: number
)
	model:SetAttribute("VehicleOwnerUserId", player.UserId)
	model:SetAttribute("VehicleInstanceId", vehicleInstanceId)
	model:SetAttribute("VehicleId", vehicleId)
	model:SetAttribute("VehicleState", state)
	model:SetAttribute("VehicleMaxHealth", maxHealth)
	model:SetAttribute("VehicleHealth", health)
	if state == "Home" then
		model:SetAttribute("VehicleOrbitAngle", nil)
		model:SetAttribute("VehicleOrbitHeight", nil)
	end
end

local function stopMotion(model: Model)
	local motion = activeMotions[model]
	if not motion then
		return
	end
	activeMotions[model] = nil
	motion.Active = false
	if motion.Connection then
		motion.Connection:Disconnect()
		motion.Connection = nil
	end
end

local function finishMotion(
	model: Model,
	motion: Motion,
	succeeded: boolean,
	reason: string?,
	onFinished: (boolean, string?) -> ()
)
	if activeMotions[model] ~= motion then
		return
	end
	stopMotion(model)
	onFinished(succeeded, reason)
end

local function getFallbackAngle(model: Model): number
	local token = tostring(model:GetAttribute("VehicleInstanceId") or model.Name)
	local hash = 0
	for index = 1, #token do
		hash = (hash * 31 + string.byte(token, index)) % 3600
	end
	return math.rad(hash / 10)
end

local function getOrbitAngle(model: Model, center: Vector3): number
	local savedAngle = model:GetAttribute("VehicleOrbitAngle")
	if type(savedAngle) == "number" and savedAngle == savedAngle then
		return savedAngle
	end

	local offset = model:GetPivot().Position - center
	local horizontalOffset = Vector3.new(offset.X, 0, offset.Z)
	if horizontalOffset.Magnitude > 0.01 then
		return math.atan2(horizontalOffset.Z, horizontalOffset.X)
	end
	return getFallbackAngle(model)
end

local function getOrbitHeight(model: Model): number
	local savedHeight = model:GetAttribute("VehicleOrbitHeight")
	if type(savedHeight) == "number" and savedHeight == savedHeight then
		return savedHeight
	end

	return model:GetPivot().Position.Y + NestOrbitConfigs.HeightOffset
end

local function getFrontYawOffset(model: Model): number
	local marker = model:FindFirstChild("FrontMarker", true)
	if marker and marker:IsA("BasePart") then
		local pivot = model:GetPivot()
		local localPosition = pivot:PointToObjectSpace(marker.Position)
		local horizontalFront = Vector3.new(localPosition.X, 0, localPosition.Z)
		if horizontalFront.Magnitude > 0.001 then
			-- CFrame.lookAt 的 LookVector 对应本地 -Z，
			-- 将 Marker 相对 Pivot 的方向旋到本地 -Z。
			return math.atan2(horizontalFront.X, -horizontalFront.Z)
		end
	end
	return 0
end

local function getFacingCFrame(
	model: Model,
	position: Vector3,
	direction: Vector3
): CFrame
	local horizontalDirection = Vector3.new(direction.X, 0, direction.Z)
	if horizontalDirection.Magnitude <= 0.001 then
		return CFrame.new(position)
	end

	return CFrame.lookAt(position, position + horizontalDirection, Vector3.yAxis)
		* CFrame.Angles(
			0,
			getFrontYawOffset(model) + NestOrbitConfigs.FrontYawOffset,
			0
		)
end

local function getOrbitCFrame(
	model: Model,
	center: Vector3,
	radius: number,
	angle: number,
	height: number
): CFrame
	local position = Vector3.new(
		center.X + math.cos(angle) * radius,
		height,
		center.Z + math.sin(angle) * radius
	)
	-- 到达半径后，车头沿当前角度递增的圆周切线方向运动。
	local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	return getFacingCFrame(model, position, tangent)
end

local function validateNestMotion(
	model: Model,
	nestModel: Model,
	nestId: string
): (Vector3?, number?, string?)
	if not model.Parent then
		return nil, nil, "VehicleModelUnavailable"
	end
	if not nestModel:IsDescendantOf(workspace) then
		return nil, nil, "NestUnavailable"
	end
	local radius = NestOrbitConfigs.GetRadius(nestId)
	if type(radius) ~= "number" or radius <= 0 then
		return nil, nil, "InvalidNestRadius"
	end
	return nestModel:GetPivot().Position, radius, nil
end

function VehicleRuntimeService.StartNestTravel(
	model: Model,
	nestModel: Model,
	nestId: string,
	onArrived: (boolean, string?) -> ()
): (boolean, string?)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	assert(
		typeof(nestModel) == "Instance" and nestModel:IsA("Model"),
		"nestModel 必须是 Model"
	)
	assert(type(nestId) == "string" and nestId ~= "", "nestId 必须是非空字符串")
	assert(type(onArrived) == "function", "onArrived 必须是 function")

	local center, radius, reason = validateNestMotion(model, nestModel, nestId)
	if not center or not radius then
		return false, reason
	end

	stopMotion(model)
	local startCFrame = model:GetPivot()
	local startPosition = startCFrame.Position
	local angle = getOrbitAngle(model, center)
	local orbitHeight = startPosition.Y + NestOrbitConfigs.HeightOffset
	model:SetAttribute("VehicleOrbitHeight", orbitHeight)
	local targetCFrame = getOrbitCFrame(model, center, radius, angle, orbitHeight)
	local distance = (targetCFrame.Position - startPosition).Magnitude
	local travelSpeed = NestOrbitConfigs.TravelSpeed
	if type(travelSpeed) ~= "number" or travelSpeed <= 0 then
		return false, "InvalidTravelSpeed"
	end

	model:SetAttribute("VehicleState", "Traveling")
	model:SetAttribute("VehicleOrbitAngle", angle)
	if distance <= NestOrbitConfigs.ArrivalDistance then
		model:PivotTo(targetCFrame)
		onArrived(true, nil)
		return true, nil
	end

	local motion: Motion = {
		Active = true,
		Connection = nil,
	}
	activeMotions[model] = motion
	local elapsed = 0
	local duration = distance / travelSpeed
	motion.Connection = RunService.Heartbeat:Connect(function(deltaTime)
		if activeMotions[model] ~= motion or not motion.Active then
			return
		end
		if not model.Parent then
			finishMotion(model, motion, false, "VehicleModelUnavailable", onArrived)
			return
		end
		if not nestModel:IsDescendantOf(workspace) then
			finishMotion(model, motion, false, "NestUnavailable", onArrived)
			return
		end

		elapsed += math.max(deltaTime, 0)
		local alpha = math.clamp(elapsed / duration, 0, 1)
		local position = startPosition:Lerp(targetCFrame.Position, alpha)
		local direction = center - position
		if direction.Magnitude > 0.001 then
			model:PivotTo(getFacingCFrame(model, position, direction))
		else
			model:PivotTo(targetCFrame)
		end

		if alpha >= 1 then
			model:PivotTo(targetCFrame)
			finishMotion(model, motion, true, nil, onArrived)
		end
	end)
	return true, nil
end

function VehicleRuntimeService.StartNestOrbit(
	model: Model,
	nestModel: Model,
	nestId: string,
	state: string
): (boolean, string?)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	assert(
		typeof(nestModel) == "Instance" and nestModel:IsA("Model"),
		"nestModel 必须是 Model"
	)
	assert(type(nestId) == "string" and nestId ~= "", "nestId 必须是非空字符串")
	assert(type(state) == "string" and state ~= "", "state 必须是非空字符串")

	local center, radius, reason = validateNestMotion(model, nestModel, nestId)
	if not center or not radius then
		return false, reason
	end
	local orbitPeriod = NestOrbitConfigs.OrbitPeriodSeconds
	if type(orbitPeriod) ~= "number" or orbitPeriod <= 0 then
		return false, "InvalidOrbitPeriod"
	end

	stopMotion(model)
	local angle = getOrbitAngle(model, center)
	local orbitHeight = getOrbitHeight(model)
	model:SetAttribute("VehicleState", state)
	model:SetAttribute("VehicleOrbitAngle", angle)
	model:SetAttribute("VehicleOrbitHeight", orbitHeight)
	model:PivotTo(getOrbitCFrame(model, center, radius, angle, orbitHeight))

	local motion: Motion = {
		Active = true,
		Connection = nil,
	}
	activeMotions[model] = motion
	motion.Connection = RunService.Heartbeat:Connect(function(deltaTime)
		if activeMotions[model] ~= motion or not motion.Active then
			return
		end
		if not model.Parent or not nestModel:IsDescendantOf(workspace) then
			stopMotion(model)
			return
		end
		angle += math.max(deltaTime, 0) * math.pi * 2 / orbitPeriod
		model:SetAttribute("VehicleOrbitAngle", angle)
		model:PivotTo(getOrbitCFrame(model, center, radius, angle, orbitHeight))
	end)
	return true, nil
end

function VehicleRuntimeService.CancelMotion(model: Model)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	stopMotion(model)
end

function VehicleRuntimeService.Spawn(
	player: Player,
	vehicleInstanceId: string,
	vehicleId: string,
	maxHealth: number?
): SpawnResult
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assertIdentifier(vehicleInstanceId, "vehicleInstanceId")
	assertIdentifier(vehicleId, "vehicleId")
	if player.Parent ~= Players then
		return result(false, "PlayerUnavailable", nil, nil)
	end

	local definition = VehicleCatalog.Get(vehicleId)
	if not definition then
		return result(false, "UnknownVehicle", nil, nil)
	end
	local resolvedMaxHealth = definition.MaxHealth
	if maxHealth ~= nil then
		if type(maxHealth) ~= "number" or maxHealth ~= maxHealth or maxHealth <= 0 then
			return result(false, "InvalidVehicleMaxHealth", nil, nil)
		end
		resolvedMaxHealth = maxHealth
	end

	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return result(false, plotReason or "PlayerHasNoPlot", nil, nil)
	end
	local homeCFrame, homeReason = getHomeCFrame(plot)
	if not homeCFrame then
		return result(false, homeReason or "VehicleHomeSpawnUnavailable", nil, nil)
	end

	local template, templateReason = getTemplate(vehicleId)
	if not template then
		return result(false, templateReason or "VehicleTemplateUnavailable", nil, nil)
	end

	local vehicles, runtimeReason = getOrCreateVehiclesRoot(plot)
	if not vehicles then
		return result(false, runtimeReason or "InvalidVehiclesRuntime", nil, nil)
	end

	local existing = vehicles:FindFirstChild(vehicleInstanceId)
	if existing then
		if not existing:IsA("Model") then
			return result(false, "InvalidVehicleRuntime", nil, nil)
		end
		local existingVehicleId = existing:GetAttribute("VehicleId")
		if existingVehicleId ~= nil and existingVehicleId ~= vehicleId then
			return result(false, "VehicleInstanceTypeMismatch", nil, nil)
		end
		stopMotion(existing)
		applyIdentity(
			existing,
			player,
			vehicleInstanceId,
			vehicleId,
			"Home",
			resolvedMaxHealth,
			resolvedMaxHealth
		)
		existing:PivotTo(homeCFrame)
		return result(true, nil, existing, homeCFrame)
	end

	local vehicle = template:Clone()
	vehicle.Name = vehicleInstanceId
	applyIdentity(
		vehicle,
		player,
		vehicleInstanceId,
		vehicleId,
		"Home",
		resolvedMaxHealth,
		resolvedMaxHealth
	)
	vehicle:PivotTo(homeCFrame)
	vehicle.Parent = vehicles
	return result(true, nil, vehicle, homeCFrame)
end

function VehicleRuntimeService.MoveTo(model: Model, targetCFrame: CFrame, state: string)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	assert(typeof(targetCFrame) == "CFrame", "targetCFrame 必须是 CFrame")
	assert(type(state) == "string" and state ~= "", "state 必须是非空字符串")
	stopMotion(model)
	if not model.Parent then
		return false, "VehicleModelUnavailable"
	end
	model:PivotTo(targetCFrame)
	model:SetAttribute("VehicleState", state)
	if state == "Home" then
		model:SetAttribute("VehicleOrbitAngle", nil)
		model:SetAttribute("VehicleOrbitHeight", nil)
	end
	return true, nil
end

function VehicleRuntimeService.SetHealth(model: Model, health: number)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	assert(type(health) == "number" and health == health and health >= 0, "health 无效")
	model:SetAttribute("VehicleHealth", health)
end

function VehicleRuntimeService.ReturnHome(model: Model, homeCFrame: CFrame, maxHealth: number)
	local moved, reason = VehicleRuntimeService.MoveTo(model, homeCFrame, "Home")
	if not moved then
		return false, reason
	end
	VehicleRuntimeService.SetHealth(model, maxHealth)
	return true, nil
end

function VehicleRuntimeService.Despawn(model: Model)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	stopMotion(model)
	model:Destroy()
end

function VehicleRuntimeService.DespawnInstance(
	player: Player,
	vehicleInstanceId: string
): (boolean, string?)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assertIdentifier(vehicleInstanceId, "vehicleInstanceId")
	local plot = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return true, nil
	end
	local runtime = plot:FindFirstChild("Runtime")
	local vehicles = runtime and runtime:FindFirstChild(VEHICLES_ROOT_NAME)
	if not vehicles then
		return true, nil
	end
	local instance = vehicles:FindFirstChild(vehicleInstanceId)
	if not instance then
		return true, nil
	end
	if not instance:IsA("Model") then
		return false, "InvalidVehicleRuntime"
	end
	local ownerUserId = instance:GetAttribute("VehicleOwnerUserId")
	if ownerUserId ~= nil and ownerUserId ~= player.UserId then
		return false, "VehicleOwnerMismatch"
	end
	VehicleRuntimeService.Despawn(instance)
	return true, nil
end

return VehicleRuntimeService
