--[[
	职责：组合载具 Fleet、运行时模型、Nest 单槽位、战斗和定时奖励，提供服务器派遣 API。
	输入：RegisterVehicle、Dispatch、Recall 接收 Player 和车辆/Nest ID；GetStatus/GetNestStatus 查询状态。
	输出：派遣成功、排队位置、驻留状态和战斗/奖励过程产生的服务器状态。
	内部算法：校验玩家拥有的实例 → 创建运行时载具 → 进入 Nest 行驶预留或 FIFO 队列；
	到达配置半径后开始绕圈，空 Nest 驻留或与当前驻留者战斗；一次只启动一场战斗，
	战斗结算后胜者满血驻留、败者满血回家，再处理下一名挑战者。
	不负责：UI、Remote、跨服同步或载具类型配置。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NestCatalog = require(ReplicatedStorage.Shared.Nest.NestCatalog)
local VehicleCatalog = require(ReplicatedStorage.Shared.Vehicle.VehicleCatalog)
local VehicleProgressionConfigs = require(
	ReplicatedStorage.Shared.Vehicle.VehicleProgressionConfigs
)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local NestOccupancyService = require(script.Parent.NestOccupancyService)
local NestRewardService = require(script.Parent.NestRewardService)
local VehicleBattleService = require(script.Parent.VehicleBattleService)
local VehicleFleetService = require(script.Parent.VehicleFleetService)
local VehicleRuntimeService = require(script.Parent.VehicleRuntimeService)
local ZoneStateService = require(script.Parent.ZoneStateService)

local VehicleDispatchService = {}

export type DispatchState = "Home" | "Queued" | "Occupied" | "Battle"

export type DispatchRecord = {
	Player: Player,
	VehicleInstanceId: string,
	VehicleId: string,
	Level: number,
	NestId: string,
	Model: Model,
	HomeCFrame: CFrame,
	State: DispatchState,
	MaxHealth: number,
	Health: number,
	Attack: number,
	DiamondMultiplier: number,
	OccupationId: string?,
}

export type ActionResult = {
	Succeeded: boolean,
	Reason: string?,
	VehicleInstanceId: string?,
	VehicleId: string?,
	NestId: string?,
	State: string?,
	QueuePosition: number?,
}

local activeByPlayer: { [Player]: { [string]: DispatchRecord } } = setmetatable({}, { __mode = "k" })
local started = false
local playerRestoreStarted = false
local nextOccupationSerial = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function actionResult(
	succeeded: boolean,
	reason: string?,
	record: DispatchRecord?,
	queuePosition: number?
): ActionResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		VehicleInstanceId = if record then record.VehicleInstanceId else nil,
		VehicleId = if record then record.VehicleId else nil,
		NestId = if record then record.NestId else nil,
		State = if record then record.State else nil,
		QueuePosition = queuePosition,
	}
end

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function getActiveRecords(player: Player): { [string]: DispatchRecord }
	local records = activeByPlayer[player]
	if not records then
		records = {}
		activeByPlayer[player] = records
	end
	return records
end

local function getActiveCount(player: Player): number
	local records = activeByPlayer[player]
	if not records then
		return 0
	end

	local count = 0
	for _ in records do
		count += 1
	end
	return count
end

local function getRecord(player: Player, vehicleInstanceId: string): DispatchRecord?
	local records = activeByPlayer[player]
	return if records then records[vehicleInstanceId] else nil
end

local function isVehicleFeatureUnlocked(player: Player): boolean
	return ZoneStateService.GetUnlocked(player, VehicleCatalog.UnlockRegionId)
end

local function getNestModel(nestId: string): (Model?, string?)
	local root = workspace:FindFirstChild(NestCatalog.WorldRootName)
	if not root then
		return nil, "NestRootUnavailable"
	end
	local nest = root:FindFirstChild(nestId)
	if not nest then
		return nil, "NestUnavailable"
	end
	if not nest:IsA("Model") then
		return nil, "NestInvalid"
	end
	return nest, nil
end

local function syncHealth(record: DispatchRecord)
	VehicleRuntimeService.SetHealth(record.Model, record.Health)
end

local function removeFromActive(record: DispatchRecord)
	local records = activeByPlayer[record.Player]
	if records and records[record.VehicleInstanceId] == record then
		records[record.VehicleInstanceId] = nil
		if next(records) == nil then
			activeByPlayer[record.Player] = nil
		end
	end
	VehicleFleetService.SetActive(record.Player, record.VehicleInstanceId, false)
end

local function returnHome(record: DispatchRecord)
	record.Health = record.MaxHealth
	VehicleRuntimeService.ReturnHome(record.Model, record.HomeCFrame, record.MaxHealth)
	record.State = "Home"
	if record.Model.Parent then
		record.Model:SetAttribute("VehicleState", "Home")
		syncHealth(record)
	end
end

local function releaseRecord(record: DispatchRecord, clearOccupancy: boolean)
	local state = NestOccupancyService.Get(record.NestId)
	NestOccupancyService.ClearTraveling(record.NestId, record)
	if clearOccupancy then
		if state.Occupant == record then
			NestOccupancyService.ClearOccupant(record.NestId, record)
		else
			NestOccupancyService.RemoveFromQueue(record.NestId, record)
		end
	end
	if record.OccupationId then
		NestRewardService.End(record.OccupationId, now())
		record.OccupationId = nil
	end
	returnHome(record)
	removeFromActive(record)
end

local function beginOccupation(
	record: DispatchRecord,
	nestDefinition,
	nestModel: Model,
	startedAt: number
): (boolean, string?)
	local orbitStarted, orbitReason = VehicleRuntimeService.StartNestOrbit(
		record.Model,
		nestModel,
		record.NestId,
		"Occupied"
	)
	if not orbitStarted then
		return false, orbitReason or "VehicleOrbitStartFailed"
	end

	record.State = "Occupied"
	record.Health = record.MaxHealth
	syncHealth(record)
	NestOccupancyService.SetOccupant(record.NestId, record)
	nextOccupationSerial += 1
	local occupationId = string.format(
		"%d:%s:%d",
		record.Player.UserId,
		record.VehicleInstanceId,
		nextOccupationSerial
	)
	local started, rewardReason = NestRewardService.Begin(
		occupationId,
		record.Player,
		record.NestId,
		nestDefinition.BaseIntervalSeconds,
		nestDefinition.BaseDiamonds,
		record.DiamondMultiplier,
		startedAt
	)
	if not started then
		NestOccupancyService.ClearOccupant(record.NestId, record)
		returnHome(record)
		return false, rewardReason or "NestRewardStartFailed"
	end
	record.OccupationId = occupationId
	return true, nil
end

local startNextBattle

local function startBattleAtNest(record: DispatchRecord, nestModel: Model)
	local nestId = record.NestId
	local state = NestOccupancyService.Get(nestId)
	local defender = state.Occupant
	if not defender or state.BattleActive then
		NestOccupancyService.EnqueueFront(nestId, record)
		startNextBattle(nestId, now())
		return
	end

	local orbitStarted, orbitReason = VehicleRuntimeService.StartNestOrbit(
		record.Model,
		nestModel,
		nestId,
		"Battle"
	)
	if not orbitStarted then
		warn(string.format(
			"载具进入战斗轨道失败：%s/%s (%s)",
			record.Player.Name,
			nestId,
			orbitReason or "Unknown"
		))
		releaseRecord(record, false)
		startNextBattle(nestId, now())
		return
	end

	state.BattleActive = true
	defender.State = "Battle"
	record.State = "Battle"
	if defender.Model.Parent then
		defender.Model:SetAttribute("VehicleState", "Battle")
	end

	local battle = VehicleBattleService.Begin(defender, record, function(battleResult)
		local currentState = NestOccupancyService.Get(nestId)
		currentState.BattleActive = false

		if battleResult.Outcome == "Defender" then
			defender.State = "Occupied"
			defender.Health = defender.MaxHealth
			if defender.Model.Parent then
				defender.Model:SetAttribute("VehicleState", "Occupied")
			end
			syncHealth(defender)
			releaseRecord(record, false)
		else
			if currentState.Occupant == defender then
				NestOccupancyService.ClearOccupant(nestId, defender)
			end
			releaseRecord(defender, false)
			local definition = NestCatalog.Get(nestId)
			local target = getNestModel(nestId)
			if definition
				and target
				and getRecord(record.Player, record.VehicleInstanceId) == record
			then
				local occupied, occupyReason = beginOccupation(
					record,
					definition,
					target,
					now()
				)
				if not occupied then
					warn(string.format(
						"胜者占据 Nest 失败：%s (%s)",
						nestId,
						occupyReason or "Unknown"
					))
					releaseRecord(record, false)
				end
			else
				releaseRecord(record, false)
			end
		end
		startNextBattle(nestId, now())
	end)
	if not battle.Succeeded then
		state.BattleActive = false
		defender.State = "Occupied"
		if defender.Model.Parent then
			defender.Model:SetAttribute("VehicleState", "Occupied")
		end
		VehicleRuntimeService.ReturnHome(record.Model, record.HomeCFrame, record.MaxHealth)
		record.State = "Queued"
		if record.Model.Parent then
			record.Model:SetAttribute("VehicleState", "Queued")
		end
		NestOccupancyService.EnqueueFront(nestId, record)
		warn(string.format("启动载具战斗失败：%s (%s)", nestId, battle.Reason or "Unknown"))
		startNextBattle(nestId, now())
	end
end

local function handleTravelFinished(
	record: DispatchRecord,
	succeeded: boolean,
	reason: string?
)
	local nestId = record.NestId
	local state = NestOccupancyService.Get(nestId)
	if state.Traveling ~= record then
		return
	end
	NestOccupancyService.ClearTraveling(nestId, record)
	if getRecord(record.Player, record.VehicleInstanceId) ~= record then
		return
	end
	if not succeeded then
		warn(string.format(
			"载具前往 Nest 失败：%s/%s (%s)",
			record.Player.Name,
			nestId,
			reason or "Unknown"
		))
		releaseRecord(record, false)
		startNextBattle(nestId, now())
		return
	end

	local definition = NestCatalog.Get(nestId)
	local nestModel, nestReason = getNestModel(nestId)
	if not definition or not nestModel then
		warn(string.format(
			"载具到达时 Nest 不可用：%s (%s)",
			nestId,
			nestReason or "Unknown"
		))
		releaseRecord(record, false)
		startNextBattle(nestId, now())
		return
	end

	if not state.Occupant and not state.BattleActive then
		local occupied, occupyReason = beginOccupation(
			record,
			definition,
			nestModel,
			now()
		)
		if not occupied then
			warn(string.format(
				"载具到达后占据 Nest 失败：%s (%s)",
				nestId,
				occupyReason or "Unknown"
			))
			releaseRecord(record, false)
		end
		startNextBattle(nestId, now())
		return
	end

	if state.Occupant and not state.BattleActive then
		startBattleAtNest(record, nestModel)
		return
	end

	NestOccupancyService.EnqueueFront(nestId, record)
	startNextBattle(nestId, now())
end

local function startNestTravel(record: DispatchRecord, nestModel: Model): (boolean, string?)
	local nestId = record.NestId
	local state = NestOccupancyService.Get(nestId)
	if state.Traveling then
		return false, "NestTravelBusy"
	end
	NestOccupancyService.SetTraveling(nestId, record)
	local started, reason = VehicleRuntimeService.StartNestTravel(
		record.Model,
		nestModel,
		nestId,
		function(succeeded, travelReason)
			handleTravelFinished(record, succeeded, travelReason)
		end
	)
	if not started then
		NestOccupancyService.ClearTraveling(nestId, record)
		return false, reason
	end
	return true, nil
end

startNextBattle = function(nestId: string, _currentTime: number)
	local state = NestOccupancyService.Get(nestId)
	if state.BattleActive or state.Traveling then
		return
	end

	local candidate
	while true do
		candidate = NestOccupancyService.Dequeue(nestId)
		if not candidate then
			return
		end
		if getRecord(candidate.Player, candidate.VehicleInstanceId) == candidate then
			break
		end
	end

	local nestModel, nestReason = getNestModel(nestId)
	if not nestModel then
		warn(string.format(
			"Nest 不可用，移除排队载具：%s (%s)",
			candidate.Player.Name,
			nestReason or "Unknown"
		))
		releaseRecord(candidate, false)
		startNextBattle(nestId, now())
		return
	end

	local started, reason = startNestTravel(candidate, nestModel)
	if not started then
		warn(string.format(
			"载具开始前往 Nest 失败：%s/%s (%s)",
			candidate.Player.Name,
			nestId,
			reason or "Unknown"
		))
		releaseRecord(candidate, false)
		startNextBattle(nestId, now())
	end
end

function VehicleDispatchService.RegisterVehicle(player: Player, vehicleId: string)
	assertPlayer(player)
	if not isVehicleFeatureUnlocked(player) then
		return { Succeeded = false, Reason = "R3Locked", Vehicle = nil }
	end
	return VehicleFleetService.Register(player, vehicleId)
end

function VehicleDispatchService.InitializeUnlockedPlayer(player: Player)
	assertPlayer(player)
	if player.Parent ~= Players then
		return { Succeeded = false, Reason = "PlayerUnavailable", Vehicle = nil }
	end
	if not isVehicleFeatureUnlocked(player) then
		return { Succeeded = false, Reason = "R3Locked", Vehicle = nil }
	end

	local existing = VehicleFleetService.List(player)
	if #existing > 0 then
		return { Succeeded = true, Reason = nil, Vehicle = existing[1] }
	end

	local registered = VehicleFleetService.Register(player, VehicleCatalog.DefaultVehicleId)
	if not registered.Succeeded or not registered.Vehicle then
		return registered
	end
	return registered
end

function VehicleDispatchService.Dispatch(
	player: Player,
	vehicleInstanceId: string,
	nestId: string
): ActionResult
	assertPlayer(player)
	assert(type(vehicleInstanceId) == "string" and vehicleInstanceId ~= "", "vehicleInstanceId 无效")
	assert(type(nestId) == "string" and nestId ~= "", "nestId 无效")
	if player.Parent ~= Players then
		return actionResult(false, "PlayerUnavailable", nil, nil)
	end
	if not isVehicleFeatureUnlocked(player) then
		return actionResult(false, "R3Locked", nil, nil)
	end

	local vehicle = VehicleFleetService.Get(player, vehicleInstanceId)
	if not vehicle then
		return actionResult(false, "VehicleNotOwned", nil, nil)
	end
	if vehicle.Active then
		return actionResult(false, "VehicleAlreadyDispatched", nil, nil)
	end
	if getActiveCount(player) >= VehicleCatalog.MaxDeployedVehicles then
		return actionResult(false, "DeploymentCapacityReached", nil, nil)
	end
	local definition = VehicleCatalog.Get(vehicle.VehicleId)
	local progression = VehicleProgressionConfigs.GetForVehicle(
		vehicle.VehicleId,
		vehicle.Level
	)
	if not definition or not progression then
		return actionResult(false, "UnknownVehicle", nil, nil)
	end
	local nestDefinition = NestCatalog.Get(nestId)
	if not nestDefinition then
		return actionResult(false, "UnknownNest", nil, nil)
	end
	local nestModel, nestReason = getNestModel(nestId)
	if not nestModel then
		return actionResult(false, nestReason or "NestUnavailable", nil, nil)
	end
	if NestOccupancyService.ContainsPlayer(nestId, player) then
		return actionResult(false, "PlayerAlreadyInNest", nil, nil)
	end

	local spawned = VehicleRuntimeService.Spawn(
		player,
		vehicleInstanceId,
		vehicle.VehicleId,
		progression.MaxHealth
	)
	if not spawned.Succeeded or not spawned.Model or not spawned.HomeCFrame then
		return actionResult(false, spawned.Reason or "VehicleSpawnFailed", nil, nil)
	end
	spawned.Model:SetAttribute("VehicleLevel", vehicle.Level)

	local record: DispatchRecord = {
		Player = player,
		VehicleInstanceId = vehicleInstanceId,
		VehicleId = vehicle.VehicleId,
		Level = vehicle.Level,
		NestId = nestId,
		Model = spawned.Model,
		HomeCFrame = spawned.HomeCFrame,
		State = "Queued",
		MaxHealth = progression.MaxHealth,
		Health = progression.MaxHealth,
		Attack = progression.Attack,
		DiamondMultiplier = progression.DiamondMultiplier,
		OccupationId = nil,
	}
	getActiveRecords(player)[vehicleInstanceId] = record
	VehicleFleetService.SetActive(player, vehicleInstanceId, true)

	NestOccupancyService.Enqueue(nestId, record)
	startNextBattle(nestId, now())
	return actionResult(
		true,
		nil,
		record,
		NestOccupancyService.GetQueuePosition(nestId, record)
	)
end

function VehicleDispatchService.Recall(
	player: Player,
	vehicleInstanceId: string
): ActionResult
	assertPlayer(player)
	assert(type(vehicleInstanceId) == "string" and vehicleInstanceId ~= "", "vehicleInstanceId 无效")
	if player.Parent ~= Players then
		return actionResult(false, "PlayerUnavailable", nil, nil)
	end
	local record = getRecord(player, vehicleInstanceId)
	if not record then
		return actionResult(false, "VehicleNotDispatched", nil, nil)
	end
	if record.State == "Battle" then
		return actionResult(false, "VehicleInBattle", record, nil)
	end

	local state = NestOccupancyService.Get(record.NestId)
	local wasOccupant = state.Occupant == record
	local wasTraveling = state.Traveling == record
	if wasOccupant then
		NestOccupancyService.ClearOccupant(record.NestId, record)
	elseif wasTraveling then
		NestOccupancyService.ClearTraveling(record.NestId, record)
	else
		NestOccupancyService.RemoveFromQueue(record.NestId, record)
	end
	if wasOccupant then
		state.BattleActive = false
	end
	releaseRecord(record, false)
	startNextBattle(record.NestId, now())
	return actionResult(true, nil, record, nil)
end

function VehicleDispatchService.GetStatus(player: Player, vehicleInstanceId: string)
	assertPlayer(player)
	local record = getRecord(player, vehicleInstanceId)
	if record then
		return {
			Active = true,
			VehicleInstanceId = record.VehicleInstanceId,
			VehicleId = record.VehicleId,
			Level = record.Level,
			NestId = record.NestId,
			State = record.State,
			Health = record.Health,
			MaxHealth = record.MaxHealth,
			QueuePosition = NestOccupancyService.GetQueuePosition(record.NestId, record),
		}
	end
	local vehicle = VehicleFleetService.Get(player, vehicleInstanceId)
	if not vehicle then
		return { Active = false, Reason = "VehicleNotOwned" }
	end
	local progression = VehicleProgressionConfigs.GetForVehicle(
		vehicle.VehicleId,
		vehicle.Level
	)
	return {
		Active = false,
		VehicleInstanceId = vehicle.InstanceId,
		VehicleId = vehicle.VehicleId,
		Level = vehicle.Level,
		State = "Home",
		Health = if progression then progression.MaxHealth else 0,
		MaxHealth = if progression then progression.MaxHealth else 0,
	}
end

function VehicleDispatchService.GetNestStatus(nestId: string)
	local state = NestOccupancyService.Get(nestId)
	local occupant = state.Occupant
	return {
		NestId = nestId,
		BattleActive = state.BattleActive,
		QueueCount = #state.Queue,
		Occupant = if occupant then {
			UserId = occupant.Player.UserId,
			OwnerName = occupant.Player.Name,
			VehicleInstanceId = occupant.VehicleInstanceId,
			VehicleId = occupant.VehicleId,
			State = occupant.State,
			Health = occupant.Health,
			MaxHealth = occupant.MaxHealth,
		} else nil,
	}
end

-- 重生等运行时整体重载前使用；只清理在线临时派遣，不修改持久化 Fleet。
function VehicleDispatchService.ResetPlayer(player: Player)
	assertPlayer(player)
	VehicleBattleService.CancelForPlayer(player)
	local records = activeByPlayer[player]
	if not records then
		return
	end

	local snapshot = {}
	for _, record in records do
		table.insert(snapshot, record)
	end
	for _, record in snapshot do
		if getRecord(player, record.VehicleInstanceId) ~= record then
			continue
		end
		local state = NestOccupancyService.Get(record.NestId)
		local wasOccupant = state.Occupant == record
		if wasOccupant then
			NestOccupancyService.ClearOccupant(record.NestId, record)
		else
			NestOccupancyService.RemoveFromQueue(record.NestId, record)
		end
		if wasOccupant then
			state.BattleActive = false
		end
		releaseRecord(record, false)
		if record.Model.Parent then
			VehicleRuntimeService.Despawn(record.Model)
		end
	end
	activeByPlayer[player] = nil
end

local function releasePlayer(player: Player)
	VehicleBattleService.CancelForPlayer(player)
	local records = activeByPlayer[player]
	if not records then
		return
	end

	local snapshot = {}
	for _, record in records do
		table.insert(snapshot, record)
	end
	for _, record in snapshot do
		if getRecord(player, record.VehicleInstanceId) ~= record then
			continue
		end
		local state = NestOccupancyService.Get(record.NestId)
		local wasOccupant = state.Occupant == record
		if wasOccupant then
			NestOccupancyService.ClearOccupant(record.NestId, record)
		else
			NestOccupancyService.RemoveFromQueue(record.NestId, record)
		end
		if wasOccupant then
			state.BattleActive = false
		end
		releaseRecord(record, false)
		startNextBattle(record.NestId, now())
	end
	activeByPlayer[player] = nil
end

function VehicleDispatchService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerRemoving:Connect(releasePlayer)
end

local function restorePlayer(player: Player)
	local ready = PlayerDataReadyService.Wait(player)
	if not ready or player.Parent ~= Players then
		return
	end
	local initialized = VehicleDispatchService.InitializeUnlockedPlayer(player)
	if not initialized.Succeeded and initialized.Reason ~= "R3Locked" then
		warn(string.format(
			"恢复载具功能失败：%s (%s)",
			player.Name,
			initialized.Reason or "Unknown"
		))
	end
end

function VehicleDispatchService.StartPlayerRestore()
	if playerRestoreStarted then
		return
	end
	playerRestoreStarted = true
	Players.PlayerAdded:Connect(function(player)
		task.defer(restorePlayer, player)
	end)
	for _, player in Players:GetPlayers() do
		task.defer(restorePlayer, player)
	end
end

return VehicleDispatchService
