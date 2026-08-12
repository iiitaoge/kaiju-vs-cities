--[[
	职责：管理玩家各收入区域防守怪兽的加载、付费建造、升级、回位和受占用约束的复活。
	输入：Player；建造/升级/恢复/回位传防守 SpawnPointId。
	输出：成功状态、稳定 Reason 和最新怪兽记录。
	内部算法：复用共用名册/成长/升级/移动模块，但使用 DefenseGodzilla 模板与独立持久化状态；
		死亡后仅在所属区域无敌方怪兽时开始完整 10 秒倒计时，重新占用会清零倒计时。
	不负责：进攻命令、进攻怪兽容量、区域解锁扣款、决斗选敌或客户端 UI。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterBuildButtonPresentationService = require(
	script.Parent.Button.MonsterBuildButtonPresentationService
)
local DefenseMonsterRuntimePresentation = require(script.Parent.DefenseMonsterRuntimePresentation)
local DefenseMonsterSpawnPointStateService = require(
	script.Parent.DefenseMonsterSpawnPointStateService
)
local DefenseMonsterTemplateResolver = require(script.Parent.DefenseMonsterTemplateResolver)
local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local GodzillaService = require(script.Parent.GodzillaService)
local ModelMover = require(script.Parent.ModelMover)
local MonsterRecoveryCoordinator = require(script.Parent.MonsterRecoveryCoordinator)
local MonsterReturnCoordinator = require(script.Parent.MonsterReturnCoordinator)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterUpgradeCoordinator = require(script.Parent.MonsterUpgradeCoordinator)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local PlayerRebirthBonusQuery = require(script.Parent.PlayerRebirthBonusQuery)
local PlayerRuntimeLoadReporter = require(script.Parent.Analytics.PlayerRuntimeLoadReporter)
local PlotMonsterRuntimeAccess = require(script.Parent.PlotMonsterRuntimeAccess)
local SpawnPointMonsterBinding = require(script.Parent.SpawnPointMonsterBinding)
local WorkspaceDefenseMonsterSlotAccess = require(script.Parent.WorkspaceDefenseMonsterSlotAccess)
local WorkspacePlayerRegionMonsterOccupancyQuery = require(
	script.Parent.WorkspacePlayerRegionMonsterOccupancyQuery
)
local ZoneStateService = require(script.Parent.ZoneStateService)
local BuildPresentationVisibility = require(
	ReplicatedStorage.Shared.Building.BuildPresentationVisibility
)
local ModelAnimationConfigs = require(ReplicatedStorage.Shared.Animation.ModelAnimationConfigs)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local MonsterLevelLimitRules = require(
	ReplicatedStorage.Shared.Monster.MonsterLevelLimitRules
)
local MonsterExpeditionConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionConfigs
)
local PlayerMonsterLevelLimitQuery = require(script.Parent.PlayerMonsterLevelLimitQuery)

local PlayerDefenseMonsterRuntimeCoordinator = {}

export type Result = {
	Succeeded: boolean,
	Reason: string?,
	Record: MonsterRosterCoordinator.MonsterRecord?,
	LoadedCount: number?,
}

local loadedPlots: { [Player]: Model } = setmetatable({}, { __mode = "k" })
local loadedPoints: { [Player]: { [string]: BasePart } } = setmetatable({}, { __mode = "k" })
local INITIAL_LEVEL = 1
local started = false

local function refreshBuildButtons(player: Player, plot: Model)
	local called, refreshed, reason = pcall(
		MonsterBuildButtonPresentationService.RefreshAll,
		player,
		plot
	)
	if not called then
		warn(string.format(
			"刷新防守怪兽建造按钮异常：%s (%s)",
			player.Name,
			tostring(refreshed)
		))
	elseif not refreshed then
		warn(string.format(
			"刷新防守怪兽建造按钮失败：%s (%s)",
			player.Name,
			reason or "Unknown"
		))
	end
end

local function result(succeeded: boolean, reason: string?, record, loadedCount: number?): Result
	return {
		Succeeded = succeeded,
		Reason = reason,
		Record = record,
		LoadedCount = loadedCount,
	}
end

local function resolveDefinition(spawnPointId: string, level: number)
	local monsterKey = DefenseMonsterSlotCatalog.GetMonsterKey(spawnPointId, level)
	if not monsterKey then
		return nil, nil, nil, nil, "MonsterLevelNotConfigured"
	end
	local template, monsterDefinition, modelScale, reason =
		DefenseMonsterTemplateResolver.Resolve(monsterKey)
	return monsterKey, template, monsterDefinition, modelScale, reason
end

local function applyPresentation(spawnPointId: string, model: Model): Model
	local definition = assert(DefenseMonsterSlotCatalog.Get(spawnPointId))
	return DefenseMonsterRuntimePresentation.Apply(model, definition.RegionId)
end

local function createRuntime(
	player: Player,
	plot: Model,
	spawnPointId: string,
	level: number
): Result
	local definition = DefenseMonsterSlotCatalog.Get(spawnPointId)
	if not definition then
		return result(false, "UnknownDefenseMonster", nil, nil)
	end
	if not ZoneStateService.GetUnlocked(player, definition.RegionId) then
		return result(false, "DefenseMonsterRegionLocked", nil, nil)
	end
	local existing = MonsterRosterCoordinator.Get(player, spawnPointId)
	if existing then
		if existing.Model then
			applyPresentation(spawnPointId, existing.Model)
		end
		return result(true, "AlreadyLoaded", existing, nil)
	end
	local point, pointReason = WorkspaceDefenseMonsterSlotAccess.Resolve(plot, definition.RegionId)
	if not point then
		return result(false, pointReason or "DefenseMonsterSlotUnavailable", nil, nil)
	end
	local monsterKey, template, monsterDefinition, modelScale, resolveReason =
		resolveDefinition(spawnPointId, level)
	if not monsterKey or not template or not monsterDefinition or not modelScale then
		return result(false, resolveReason or "DefenseMonsterResolveFailed", nil, nil)
	end
	local runtimeRoot, runtimeReason = PlotMonsterRuntimeAccess.GetOrCreate(plot)
	if not runtimeRoot then
		return result(false, runtimeReason or "MonsterRuntimeUnavailable", nil, nil)
	end
	local maxHealth = monsterDefinition.MaxHealth
		* PlayerRebirthBonusQuery.Get(player).MonsterHealthMultiplier
	local created = MonsterRosterCoordinator.RestoreForSpawnPoint(
		player,
		spawnPointId,
		monsterKey,
		template,
		modelScale,
		point,
		point.CFrame,
		maxHealth,
		runtimeRoot
	)
	if not created.Succeeded or not created.Record or not created.Record.Model then
		return result(false, created.Reason or "DefenseMonsterCreateFailed", created.Record, nil)
	end
	loadedPoints[player] = loadedPoints[player] or {}
	loadedPoints[player][spawnPointId] = point
	applyPresentation(spawnPointId, created.Record.Model)
	return result(true, nil, created.Record, nil)
end

function PlayerDefenseMonsterRuntimeCoordinator.Load(player: Player): Result
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local ready, readyReason = PlayerDataReadyService.Wait(player)
	if not ready then
		return result(false, readyReason or "PlayerDataUnavailable", nil, 0)
	end
	if player.Parent ~= Players then
		return result(false, "PlayerUnavailable", nil, 0)
	end
	if loadedPlots[player] then
		return result(true, "AlreadyLoaded", nil, 0)
	end
	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return result(false, plotReason or "PlayerHasNoPlot", nil, 0)
	end

	loadedPlots[player] = plot
	loadedPoints[player] = {}
	local createdIds = {}
	for _, state in DefenseMonsterSpawnPointStateService.List(player) do
		if not state.Built then
			continue
		end
		local created = createRuntime(player, plot, state.SpawnPointId, state.Level)
		if not created.Succeeded then
			for _, createdId in createdIds do
				local point = loadedPoints[player][createdId]
				if point then
					SpawnPointMonsterBinding.Unbind(point, createdId)
				end
				MonsterRosterCoordinator.UnloadForSpawnPoint(player, createdId, true)
			end
			loadedPoints[player] = nil
			loadedPlots[player] = nil
			return result(false, (created.Reason or "DefenseMonsterLoadFailed") .. ":" .. state.SpawnPointId, nil, 0)
		end
		table.insert(createdIds, state.SpawnPointId)
	end
	refreshBuildButtons(player, plot)
	return result(true, nil, nil, #createdIds)
end

local function prepareBuild(player: Player, spawnPointId: string)
	local definition = DefenseMonsterSlotCatalog.Get(spawnPointId)
	if not definition then
		return nil, "UnknownDefenseMonster"
	end
	if not ZoneStateService.GetUnlocked(player, definition.RegionId) then
		return nil, "DefenseMonsterRegionLocked"
	end
	local plot = loadedPlots[player]
	if not plot then
		return nil, "DefenseMonsterRuntimeNotLoaded"
	end
	local state = DefenseMonsterSpawnPointStateService.Get(player, spawnPointId)
	if state.Built then
		return nil, "DefenseMonsterAlreadyBuilt"
	end
	if MonsterRosterCoordinator.Get(player, spawnPointId) then
		return nil, "DefenseMonsterAlreadyLoaded"
	end
	local point, pointReason = WorkspaceDefenseMonsterSlotAccess.Resolve(
		plot,
		definition.RegionId
	)
	if not point then
		return nil, pointReason or "DefenseMonsterSlotUnavailable"
	end
	local monsterKey, template, monsterDefinition, modelScale, resolveReason = resolveDefinition(
		spawnPointId,
		INITIAL_LEVEL
	)
	if not monsterKey or not template or not monsterDefinition or not modelScale then
		return nil, resolveReason or "DefenseMonsterResolveFailed"
	end
	return {
		Plot = plot,
		MonsterKey = monsterKey,
	}, nil
end

function PlayerDefenseMonsterRuntimeCoordinator.CanBuild(player: Player, spawnPointId: string)
	local plan, reason = prepareBuild(player, spawnPointId)
	return {
		Allowed = plan ~= nil,
		Reason = reason,
		TargetLevel = INITIAL_LEVEL,
		MonsterKey = if plan then plan.MonsterKey else nil,
	}
end

function PlayerDefenseMonsterRuntimeCoordinator.Build(player: Player, spawnPointId: string): Result
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 必须是非空字符串")
	local plan, planReason = prepareBuild(player, spawnPointId)
	if not plan then
		return result(
			false,
			planReason or "DefenseMonsterBuildUnavailable",
			MonsterRosterCoordinator.Get(player, spawnPointId),
			nil
		)
	end
	local created = createRuntime(player, plan.Plot, spawnPointId, INITIAL_LEVEL)
	if not created.Succeeded then
		return created
	end
	DefenseMonsterSpawnPointStateService.MarkBuilt(
		player,
		spawnPointId,
		INITIAL_LEVEL,
		plan.MonsterKey
	)
	refreshBuildButtons(player, plan.Plot)
	return created
end

local function prepareUpgrade(player: Player, spawnPointId: string, targetLevel: number)
	local definition = DefenseMonsterSlotCatalog.Get(spawnPointId)
	if not definition then
		return nil, "UnknownDefenseMonster"
	end
	local state = DefenseMonsterSpawnPointStateService.Get(player, spawnPointId)
	if not state.Built then
		return nil, "DefenseMonsterNotBuilt"
	end
	if targetLevel <= state.Level then
		return nil, "InvalidUpgradeLevel"
	end
	local levelLimit = assert(PlayerMonsterLevelLimitQuery.Get(player, definition.ProgressionId))
	local levelAllowed, levelReason = MonsterLevelLimitRules.CheckTargetLevel(
		targetLevel,
		levelLimit.MaxLevel,
		levelLimit.TotalMaxLevel
	)
	if not levelAllowed then
		return nil, levelReason
	end
	local newMonsterKey = DefenseMonsterSlotCatalog.GetMonsterKey(spawnPointId, targetLevel)
	if not newMonsterKey then
		return nil, "MaxLevel"
	end
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not record then
		return nil, "MonsterUnavailable"
	end
	local plot = loadedPlots[player]
	if not plot then
		return nil, "DefenseMonsterRuntimeNotLoaded"
	end
	local point, pointReason = WorkspaceDefenseMonsterSlotAccess.Resolve(plot, definition.RegionId)
	if not point then
		return nil, pointReason or "DefenseMonsterSlotUnavailable"
	end
	local template, monsterDefinition, modelScale, resolveReason =
		DefenseMonsterTemplateResolver.Resolve(newMonsterKey)
	if not template or not monsterDefinition or not modelScale then
		return nil, resolveReason or "DefenseMonsterResolveFailed"
	end
	local templateChanged = MonsterCatalog.HasTemplateChanged(record.MonsterKey, newMonsterKey)
	if templateChanged == nil then
		return nil, "MonsterTemplateComparisonUnavailable"
	end
	return {
		MonsterKey = newMonsterKey,
		Template = template,
		ModelScale = modelScale,
		Point = point,
		MaxHealth = monsterDefinition.MaxHealth
			* PlayerRebirthBonusQuery.Get(player).MonsterHealthMultiplier,
		TemplateChanged = templateChanged,
	}, nil
end

function PlayerDefenseMonsterRuntimeCoordinator.CanUpgrade(
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

function PlayerDefenseMonsterRuntimeCoordinator.Upgrade(
	player: Player,
	spawnPointId: string,
	targetLevel: number
): Result
	local plan, planReason = prepareUpgrade(player, spawnPointId, targetLevel)
	if not plan then
		return result(false, planReason or "DefenseMonsterUpgradeUnavailable", MonsterRosterCoordinator.Get(player, spawnPointId), nil)
	end
	local upgraded = MonsterUpgradeCoordinator.Execute(
		player,
		spawnPointId,
		plan.MonsterKey,
		plan.Template,
		plan.ModelScale,
		plan.Point,
		plan.Point.CFrame,
		plan.MaxHealth,
		plan.TemplateChanged
	)
	if not upgraded.Succeeded or not upgraded.Record or not upgraded.Record.Model then
		return result(false, upgraded.Reason or "DefenseMonsterUpgradeFailed", upgraded.Record, nil)
	end
	if plan.TemplateChanged then
		BuildPresentationVisibility.Restore(upgraded.Record.Model)
	end
	applyPresentation(spawnPointId, upgraded.Record.Model)
	DefenseMonsterSpawnPointStateService.MarkBuilt(
		player,
		spawnPointId,
		targetLevel,
		plan.MonsterKey
	)
	return result(true, nil, upgraded.Record, nil)
end

function PlayerDefenseMonsterRuntimeCoordinator.BeginRecovery(player: Player, spawnPointId: string)
	local definition = DefenseMonsterSlotCatalog.Get(spawnPointId)
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not definition or not record then
		return result(false, "UnknownDefenseMonster", record, nil)
	end
	local config = MonsterExpeditionConfigs[record.MonsterKey]
	if not config then
		return result(false, "MonsterRecoveryConfigUnavailable", record, nil)
	end
	local recovery = MonsterRecoveryCoordinator.Begin(player, spawnPointId, {
		RecoveryDuration = config.RecoveryDuration,
		PollInterval = 0.25,
		CanStartCountdown = function()
			return not WorkspacePlayerRegionMonsterOccupancyQuery.IsOccupied(
				player,
				definition.RegionId
			)
		end,
		ResolveTemplate = function(monsterKey)
			local template, _, modelScale = DefenseMonsterTemplateResolver.Resolve(monsterKey)
			return template, modelScale
		end,
		OnRespawned = function(_player, _spawnPointId, model)
			applyPresentation(spawnPointId, model)
		end,
	})
	return result(recovery.Succeeded, recovery.Reason, MonsterRosterCoordinator.Get(player, spawnPointId), nil)
end

function PlayerDefenseMonsterRuntimeCoordinator.ReturnToSlot(player: Player, spawnPointId: string)
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not record then
		return { Succeeded = false, Reason = "MonsterUnavailable" }
	end
	local animation = ModelAnimationConfigs[record.MonsterKey]
	local config = MonsterExpeditionConfigs[record.MonsterKey]
	if not animation or not config then
		return { Succeeded = false, Reason = "MonsterMovementConfigUnavailable" }
	end
	local movement = config.Movement
	return MonsterReturnCoordinator.Begin(player, spawnPointId, {
		ExecuteReturn = function(model, spawnCFrame)
			local moved = GodzillaMoveService.MoveTo(model, spawnCFrame.Position, {
				MoveSpeed = movement.MoveSpeed,
				MaxTravelDuration = movement.MaxTravelDuration,
				TimingSafetyMargin = movement.TimingSafetyMargin,
				TurnDuration = movement.TurnDuration,
				SetMoving = function(isMoving, moveSpeed)
					GodzillaService.SetMoving(
						model,
						animation,
						isMoving,
						moveSpeed,
						movement.WalkAnimation
					)
				end,
			})
			if not moved and model.Parent then
				ModelMover.Snap(model, spawnCFrame)
				moved = true
			end
			if moved and model.Parent then
				-- MoveTo 只保证到达出生点位置；最终用出生点 CFrame 校正朝向。
				ModelMover.Snap(model, spawnCFrame)
			end
			return { Succeeded = moved, Reason = if moved then nil else "DefenseMonsterReturnFailed" }
		end,
		OnReturned = function(_player, _spawnPointId, model)
			GodzillaService.StopMoving(model)
			applyPresentation(spawnPointId, model)
		end,
	})
end

local function unload(player: Player, clearMonsterState: boolean): number
	local points = loadedPoints[player]
	local removedCount = 0
	if points then
		for spawnPointId, point in pairs(points) do
			SpawnPointMonsterBinding.Unbind(point, spawnPointId)
			if MonsterRosterCoordinator.UnloadForSpawnPoint(player, spawnPointId, clearMonsterState) then
				removedCount += 1
			end
		end
	end
	loadedPoints[player] = nil
	loadedPlots[player] = nil
	return removedCount
end

function PlayerDefenseMonsterRuntimeCoordinator.Unload(player: Player): number
	return unload(player, true)
end

local function loadAndWarn(player: Player)
	local loadResult = PlayerDefenseMonsterRuntimeCoordinator.Load(player)
	PlayerRuntimeLoadReporter.Report(player, "DefenseMonster", loadResult.Succeeded, loadResult.Reason)
	if not loadResult.Succeeded then
		warn(string.format("加载玩家 %s 防守怪兽失败：%s", player.Name, loadResult.Reason or "Unknown"))
	end
end

function PlayerDefenseMonsterRuntimeCoordinator.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(function(player)
		task.defer(loadAndWarn, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		unload(player, false)
	end)
	for _, player in Players:GetPlayers() do
		loadAndWarn(player)
	end
end

return PlayerDefenseMonsterRuntimeCoordinator
