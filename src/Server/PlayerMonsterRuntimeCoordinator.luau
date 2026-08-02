--[[
	职责：
	- 把玩家已建造的怪兽出生点状态恢复为服务器权威怪兽。
	- 执行“建造出生点即新增怪兽”和“升级出生点替换怪兽”的完整服务器链路。

	输入：
	- Load / Unload：已经分配 Plot 的 Player。
	- Build：Player、SpawnPointId。
	- Upgrade：Player、SpawnPointId、目标等级。

	输出：
	- 怪兽生成在 Plot/Runtime/Monsters。
	- 返回 Succeeded、稳定 Reason，以及对应怪兽记录。

	内部算法：
	- 读取出生点配置、保存状态和已解锁 MonsterSpawnPoint Slot。
	- 解析 MonsterKey 对应模板，再协调怪兽名册完成创建或替换。
	- Build 由名册容量规则拒绝超限；Load 恢复既有资产，不因容量后来降低而删除怪兽。

	不负责：建造价格、容量升级价格、攻击 UI、存档读写或表现动画。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterSpawnPointStateService = require(script.Parent.MonsterSpawnPointStateService)
local MonsterTemplateResolver = require(script.Parent.MonsterTemplateResolver)
local MonsterUpgradeCoordinator = require(script.Parent.MonsterUpgradeCoordinator)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlotMonsterRuntimeAccess = require(script.Parent.PlotMonsterRuntimeAccess)
local SpawnPointMonsterBinding = require(script.Parent.SpawnPointMonsterBinding)
local WorkspacePlayerWorldAccess = require(script.Parent.WorkspacePlayerWorldAccess)
local ZoneStateService = require(script.Parent.ZoneStateService)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)
local MonsterCapacityRules = require(ReplicatedStorage.Shared.Monster.MonsterCapacityRules)
local MonsterStateRules = require(ReplicatedStorage.Shared.Monster.MonsterStateRules)

local PlayerMonsterRuntimeCoordinator = {}

export type Result = {
	Succeeded: boolean,
	Reason: string?,
	Record: MonsterRosterCoordinator.MonsterRecord?,
	LoadedCount: number?,
}

type PlanItem = {
	SpawnPointId: string,
	MonsterKey: string,
	Template: Model,
	MaxHealth: number,
	Point: BasePart,
}

type RuntimeActionPlan = {
	SpawnPointId: string,
	TargetLevel: number,
	MonsterKey: string,
	Template: Model,
	MaxHealth: number,
	Point: BasePart,
	RuntimeRoot: Folder,
}

local SLOT_KIND = "MonsterSpawnPoint"
local INITIAL_LEVEL = 1
local loadedPlots: { [Player]: Model } = setmetatable({}, { __mode = "k" })
local loadedPoints: { [Player]: { [string]: BasePart } } = setmetatable({}, { __mode = "k" })
local started = false

local function result(
	succeeded: boolean,
	reason: string?,
	record: MonsterRosterCoordinator.MonsterRecord?,
	loadedCount: number?
): Result
	return {
		Succeeded = succeeded,
		Reason = reason,
		Record = record,
		LoadedCount = loadedCount,
	}
end

local function getUnlockedPoints(player: Player): ({ [string]: BasePart }?, string?)
	local points = {}
	for _, slot in WorkspacePlayerWorldAccess.Slots.ListUnlockedSlots(player, SLOT_KIND) do
		if points[slot.SlotId] then
			return nil, "DuplicateMonsterSpawnPoint:" .. slot.SlotId
		end
		points[slot.SlotId] = slot.Point
	end
	return points, nil
end

local function getPoint(player: Player, spawnPointId: string): (BasePart?, string?)
	local definition = MonsterSpawnPointCatalog.Get(spawnPointId)
	if not definition then
		return nil, "UnknownSpawnPoint"
	end
	if not ZoneStateService.GetUnlocked(player, definition.ZoneId) then
		return nil, "MonsterZoneLocked"
	end

	local points, pointsReason = getUnlockedPoints(player)
	if not points then
		return nil, pointsReason
	end
	local point = points[definition.SlotId]
	if not point then
		return nil, "MissingMonsterSpawnPoint:" .. definition.SlotId
	end
	return point, nil
end

local function resolveDefinition(spawnPointId: string, level: number)
	local monsterKey = MonsterSpawnPointCatalog.GetMonsterKey(spawnPointId, level)
	if not monsterKey then
		return nil, nil, nil, "MonsterLevelNotConfigured"
	end
	local template, monsterDefinition, templateReason = MonsterTemplateResolver.Resolve(monsterKey)
	if not template then
		return nil, nil, monsterDefinition, templateReason
	end
	if not template.PrimaryPart then
		return nil, nil, monsterDefinition, "MonsterTemplateMissingPrimaryPart"
	end
	return monsterKey, template, monsterDefinition, nil
end

local function createLoadPlan(player: Player): ({ PlanItem }?, string?)
	local points, pointsReason = getUnlockedPoints(player)
	if not points then
		return nil, pointsReason
	end

	local plan = {}
	for _, state in MonsterSpawnPointStateService.List(player) do
		if not state.Built then
			continue
		end

		local definition = MonsterSpawnPointCatalog.Get(state.SpawnPointId)
		if not definition then
			return nil, "UnknownBuiltSpawnPoint:" .. state.SpawnPointId
		end
		if not ZoneStateService.GetUnlocked(player, definition.ZoneId) then
			return nil, "BuiltSpawnPointInLockedZone:" .. state.SpawnPointId
		end
		local point = points[definition.SlotId]
		if not point then
			return nil, "MissingMonsterSpawnPoint:" .. definition.SlotId
		end

		local monsterKey, template, monsterDefinition, resolveReason = resolveDefinition(
			state.SpawnPointId,
			state.Level
		)
		if not monsterKey or not template or not monsterDefinition then
			return nil, (resolveReason or "MonsterResolveFailed") .. ":" .. state.SpawnPointId
		end
		if state.MonsterKey ~= monsterKey then
			return nil, "MonsterSpawnPointStateMismatch:" .. state.SpawnPointId
		end

		table.insert(plan, {
			SpawnPointId = state.SpawnPointId,
			MonsterKey = monsterKey,
			Template = template,
			MaxHealth = monsterDefinition.MaxHealth,
			Point = point,
		})
	end
	return plan, nil
end

local function prepareBuild(player: Player, spawnPointId: string): (RuntimeActionPlan?, string?)
	if not loadedPlots[player] then
		return nil, "MonsterRuntimeNotLoaded"
	end
	if not MonsterSpawnPointCatalog.Get(spawnPointId) then
		return nil, "UnknownSpawnPoint"
	end
	local state = MonsterSpawnPointStateService.Get(player, spawnPointId)
	if state.Built then
		return nil, "SpawnPointAlreadyBuilt"
	end

	local capacity = MonsterCapacityRules.CheckAdd(
		MonsterRosterCoordinator.GetCount(player),
		MonsterRosterCoordinator.GetCapacity(player)
	)
	if not capacity.Allowed then
		return nil, capacity.Reason
	end
	local point, pointReason = getPoint(player, spawnPointId)
	if not point then
		return nil, pointReason or "MonsterSpawnPointUnavailable"
	end
	local monsterKey, template, monsterDefinition, resolveReason = resolveDefinition(
		spawnPointId,
		INITIAL_LEVEL
	)
	if not monsterKey or not template or not monsterDefinition then
		return nil, resolveReason or "MonsterResolveFailed"
	end
	local runtimeRoot = PlotMonsterRuntimeAccess.Get(loadedPlots[player])
	if not runtimeRoot then
		return nil, "MonsterRuntimeUnavailable"
	end
	return {
		SpawnPointId = spawnPointId,
		TargetLevel = INITIAL_LEVEL,
		MonsterKey = monsterKey,
		Template = template,
		MaxHealth = monsterDefinition.MaxHealth,
		Point = point,
		RuntimeRoot = runtimeRoot,
	}, nil
end

local function prepareUpgrade(
	player: Player,
	spawnPointId: string,
	targetLevel: number
): (RuntimeActionPlan?, string?)
	if not loadedPlots[player] then
		return nil, "MonsterRuntimeNotLoaded"
	end
	if not MonsterSpawnPointCatalog.Get(spawnPointId) then
		return nil, "UnknownSpawnPoint"
	end
	local state = MonsterSpawnPointStateService.Get(player, spawnPointId)
	if not state.Built then
		return nil, "SpawnPointNotBuilt"
	end
	if targetLevel ~= state.Level + 1 then
		return nil, "InvalidUpgradeLevel"
	end
	if not MonsterSpawnPointCatalog.GetMonsterKey(spawnPointId, targetLevel) then
		return nil, "MaxLevel"
	end

	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not record then
		return nil, "UnknownSpawnPoint"
	end
	local permission = MonsterStateRules.CheckUpgrade(record.State)
	if not permission.Allowed then
		return nil, permission.Reason
	end
	local point, pointReason = getPoint(player, spawnPointId)
	if not point then
		return nil, pointReason or "MonsterSpawnPointUnavailable"
	end
	local monsterKey, template, monsterDefinition, resolveReason = resolveDefinition(
		spawnPointId,
		targetLevel
	)
	if not monsterKey or not template or not monsterDefinition then
		return nil, resolveReason or "MonsterResolveFailed"
	end
	local runtimeRoot = PlotMonsterRuntimeAccess.Get(loadedPlots[player])
	if not runtimeRoot then
		return nil, "MonsterRuntimeUnavailable"
	end
	return {
		SpawnPointId = spawnPointId,
		TargetLevel = targetLevel,
		MonsterKey = monsterKey,
		Template = template,
		MaxHealth = monsterDefinition.MaxHealth,
		Point = point,
		RuntimeRoot = runtimeRoot,
	}, nil
end

function PlayerMonsterRuntimeCoordinator.Load(player: Player): Result
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local ready, readyReason = PlayerDataReadyService.Wait(player)
	if not ready then
		return result(false, readyReason or "PlayerDataUnavailable", nil, 0)
	end
	if player.Parent ~= Players then
		return result(false, "PlayerUnavailable", nil, 0)
	end
	if loadedPlots[player] then
		return result(true, "AlreadyLoaded", nil, #MonsterRosterCoordinator.List(player))
	end

	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return result(false, plotReason or "PlayerHasNoPlot", nil, 0)
	end
	local runtimeRoot, runtimeReason = PlotMonsterRuntimeAccess.GetOrCreate(plot)
	if not runtimeRoot then
		return result(false, runtimeReason or "MonsterRuntimeUnavailable", nil, 0)
	end
	local plan, planReason = createLoadPlan(player)
	if not plan then
		return result(false, planReason or "MonsterLoadPlanFailed", nil, 0)
	end

	local createdItems = {}
	local points = {}
	for _, item in plan do
		local created = MonsterRosterCoordinator.RestoreForSpawnPoint(
			player,
			item.SpawnPointId,
			item.MonsterKey,
			item.Template,
			item.Point,
			item.MaxHealth,
			runtimeRoot
		)
		if not created.Succeeded then
			for index = #createdItems, 1, -1 do
				local rollbackItem = createdItems[index]
				MonsterRosterCoordinator.RemoveForSpawnPoint(
					player,
					rollbackItem.SpawnPointId,
					rollbackItem.Point
				)
			end
			return result(false, (created.Reason or "MonsterCreateFailed") .. ":" .. item.SpawnPointId, nil, 0)
		end
		table.insert(createdItems, item)
		points[item.SpawnPointId] = item.Point
	end

	loadedPlots[player] = plot
	loadedPoints[player] = points
	return result(true, nil, nil, #createdItems)
end

function PlayerMonsterRuntimeCoordinator.Build(player: Player, spawnPointId: string): Result
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 必须是非空字符串")
	local plan, planReason = prepareBuild(player, spawnPointId)
	if not plan then
		return result(false, planReason or "MonsterBuildUnavailable", MonsterRosterCoordinator.Get(player, spawnPointId), nil)
	end
	local created = MonsterRosterCoordinator.CreateForSpawnPoint(
		player,
		spawnPointId,
		plan.MonsterKey,
		plan.Template,
		plan.Point,
		plan.MaxHealth,
		plan.RuntimeRoot
	)
	if not created.Succeeded then
		return result(false, created.Reason, created.Record, nil)
	end

	MonsterSpawnPointStateService.MarkBuilt(player, spawnPointId, plan.TargetLevel, plan.MonsterKey)
	loadedPoints[player] = loadedPoints[player] or {}
	loadedPoints[player][spawnPointId] = plan.Point
	return result(true, nil, created.Record, nil)
end

function PlayerMonsterRuntimeCoordinator.CanBuild(player: Player, spawnPointId: string)
	local plan, reason = prepareBuild(player, spawnPointId)
	return {
		Allowed = plan ~= nil,
		Reason = reason,
		TargetLevel = if plan then plan.TargetLevel else INITIAL_LEVEL,
		MonsterKey = if plan then plan.MonsterKey else nil,
	}
end

function PlayerMonsterRuntimeCoordinator.Upgrade(
	player: Player,
	spawnPointId: string,
	targetLevel: number
): Result
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 必须是非空字符串")
	assert(
		type(targetLevel) == "number" and targetLevel >= 1 and targetLevel % 1 == 0,
		"targetLevel 必须是正整数"
	)
	local plan, planReason = prepareUpgrade(player, spawnPointId, targetLevel)
	if not plan then
		return result(false, planReason or "MonsterUpgradeUnavailable", MonsterRosterCoordinator.Get(player, spawnPointId), nil)
	end

	local upgraded = MonsterUpgradeCoordinator.Execute(
		player,
		spawnPointId,
		plan.MonsterKey,
		plan.Template,
		plan.Point,
		plan.MaxHealth
	)
	if not upgraded.Succeeded then
		return result(false, upgraded.Reason, upgraded.Record, nil)
	end
	MonsterSpawnPointStateService.MarkBuilt(player, spawnPointId, targetLevel, plan.MonsterKey)
	return result(true, nil, upgraded.Record, nil)
end

function PlayerMonsterRuntimeCoordinator.CanUpgrade(
	player: Player,
	spawnPointId: string,
	targetLevel: number
)
	local plan, reason = prepareUpgrade(player, spawnPointId, targetLevel)
	return {
		Allowed = plan ~= nil,
		Reason = reason,
		TargetLevel = targetLevel,
		MonsterKey = if plan then plan.MonsterKey else nil,
	}
end

local function unload(player: Player, clearMonsterState: boolean): number
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local points = loadedPoints[player]
	if points then
		for spawnPointId, point in pairs(points) do
			SpawnPointMonsterBinding.Unbind(point, spawnPointId)
		end
	end
	loadedPoints[player] = nil

	local removedCount = MonsterRosterCoordinator.UnloadRuntime(player, clearMonsterState)
	local plot = loadedPlots[player]
	loadedPlots[player] = nil
	local runtimeRoot = plot and PlotMonsterRuntimeAccess.Get(plot)
	if runtimeRoot then
		runtimeRoot:Destroy()
	end
	return removedCount
end

-- 公开 Unload 用于同一玩家的显式运行时重载，因此会清除可由出生点保存状态重建的 Monsters 会话状态。
function PlayerMonsterRuntimeCoordinator.Unload(player: Player): number
	return unload(player, true)
end

local function loadAndWarn(player: Player)
	local loadResult = PlayerMonsterRuntimeCoordinator.Load(player)
	if not loadResult.Succeeded then
		warn(string.format("加载玩家 %s 怪兽失败：%s", player.Name, loadResult.Reason or "Unknown"))
	end
end

function PlayerMonsterRuntimeCoordinator.Start()
	if started then
		return
	end
	started = true
	MonsterRosterCoordinator.Start()

	Players.PlayerAdded:Connect(function(player)
		task.defer(loadAndWarn, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- 离服时 PlayerStateService 会删除整棵状态，避免在事件顺序中重新创建状态目录。
		unload(player, false)
	end)
	for _, player in Players:GetPlayers() do
		loadAndWarn(player)
	end
end

return PlayerMonsterRuntimeCoordinator
