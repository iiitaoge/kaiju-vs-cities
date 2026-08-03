--[[
	职责：
	- 把玩家已建造的怪兽出生点状态恢复为服务器权威罐体和怪兽。
	- 执行“先建造罐体再建造怪兽”和“拆除旧怪兽表现再建造新怪兽”的完整服务器链路。

	输入：
	- Load / Unload：已经分配 Plot 的 Player。
	- Build：Player、SpawnPointId。
	- Upgrade：Player、SpawnPointId、目标等级。

	输出：
	- 罐体生成在 Plot/Runtime/MonsterIncubators，怪兽生成在 Plot/Runtime/Monsters。
	- 返回 Succeeded、稳定 Reason，以及对应怪兽记录。

	内部算法：
	- 读取出生点配置、保存状态和已解锁 MonsterSpawnPoint Slot。
	- 先协调罐体建造/恢复，再解析 MonsterKey 模板并由怪兽名册创建或替换；
	  首次建造等待罐体表现完成后才创建怪兽；升级只在模板变化时播放拆除加建造表现。
	- Build 由名册容量规则拒绝超限；Load 恢复既有资产，不因容量后来降低而删除怪兽。

	不负责：建造价格、容量升级价格、攻击 UI 或存档读写。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterBuildPresentationPublisher = require(
	script.Parent.MonsterBuildPresentationPublisher
)
local MonsterIncubatorBuildCoordinator = require(script.Parent.MonsterIncubatorBuildCoordinator)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterSpawnPointStateService = require(script.Parent.MonsterSpawnPointStateService)
local MonsterTemplateResolver = require(script.Parent.MonsterTemplateResolver)
local MonsterUpgradeCoordinator = require(script.Parent.MonsterUpgradeCoordinator)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlotMonsterRuntimeAccess = require(script.Parent.PlotMonsterRuntimeAccess)
local SpawnPointMonsterBinding = require(script.Parent.SpawnPointMonsterBinding)
local WorkspaceMonsterIncubatorAccess = require(script.Parent.WorkspaceMonsterIncubatorAccess)
local WorkspacePlayerWorldAccess = require(script.Parent.WorkspacePlayerWorldAccess)
local ZoneStateService = require(script.Parent.ZoneStateService)
local BuildingPresentationConfigs = require(
	ReplicatedStorage.Shared.Building.BuildingPresentationConfigs
)
local MonsterIncubatorConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorConfigs
)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
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
	Plot: Model,
	SpawnPointId: string,
	TargetLevel: number,
	MonsterKey: string,
	Template: Model,
	MaxHealth: number,
	Point: BasePart,
	RuntimeRoot: Folder,
	PresentationId: string,
	RiseDuration: number,
	DemolishDuration: number,
	PreviousMonsterKey: string?,
	TemplateChanged: boolean,
}

type CreatedLoadItem = {
	Plan: PlanItem,
	Incubator: Model,
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

local function resolvePresentation(spawnPointId: string)
	local config = MonsterIncubatorConfigs[spawnPointId]
	if not config then
		return nil, nil, "IncubatorConfigUnavailable"
	end
	local presentation = BuildingPresentationConfigs[config.PresentationId]
	if not presentation then
		return nil, nil, "MonsterBuildPresentationUnavailable"
	end
	return config.PresentationId, presentation, nil
end

local function createLoadPlan(player: Player, plot: Model): ({ PlanItem }?, string?)
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
		local incubatorCheck = MonsterIncubatorBuildCoordinator.Validate(
			plot,
			state.SpawnPointId
		)
		if not incubatorCheck.Succeeded then
			return nil, (incubatorCheck.Reason or "MonsterIncubatorUnavailable")
				.. ":"
				.. state.SpawnPointId
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
	local plot = loadedPlots[player]
	if not plot then
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
	local incubatorCheck = MonsterIncubatorBuildCoordinator.Validate(plot, spawnPointId)
	if not incubatorCheck.Succeeded then
		return nil, incubatorCheck.Reason or "MonsterIncubatorUnavailable"
	end
	local runtimeRoot = PlotMonsterRuntimeAccess.Get(plot)
	if not runtimeRoot then
		return nil, "MonsterRuntimeUnavailable"
	end
	local presentationId, presentation, presentationReason = resolvePresentation(spawnPointId)
	if not presentationId or not presentation then
		return nil, presentationReason or "MonsterBuildPresentationUnavailable"
	end
	return {
		Plot = plot,
		SpawnPointId = spawnPointId,
		TargetLevel = INITIAL_LEVEL,
		MonsterKey = monsterKey,
		Template = template,
		MaxHealth = monsterDefinition.MaxHealth,
		Point = point,
		RuntimeRoot = runtimeRoot,
		PresentationId = presentationId,
		RiseDuration = presentation.Rise.TotalDuration,
		DemolishDuration = presentation.Demolish.TotalDuration,
		PreviousMonsterKey = nil,
		TemplateChanged = true,
	}, nil
end

local function prepareUpgrade(
	player: Player,
	spawnPointId: string,
	targetLevel: number
): (RuntimeActionPlan?, string?)
	local plot = loadedPlots[player]
	if not plot then
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
	local incubator, incubatorReason = WorkspaceMonsterIncubatorAccess.Resolve(
		plot,
		spawnPointId
	)
	if not incubator then
		return nil, incubatorReason or "MonsterIncubatorUnavailable"
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
	local templateChanged = MonsterCatalog.HasTemplateChanged(record.MonsterKey, monsterKey)
	if templateChanged == nil then
		return nil, "MonsterTemplateComparisonUnavailable"
	end
	local runtimeRoot = PlotMonsterRuntimeAccess.Get(plot)
	if not runtimeRoot then
		return nil, "MonsterRuntimeUnavailable"
	end
	local presentationId, presentation, presentationReason = resolvePresentation(spawnPointId)
	if not presentationId or not presentation then
		return nil, presentationReason or "MonsterBuildPresentationUnavailable"
	end
	return {
		Plot = plot,
		SpawnPointId = spawnPointId,
		TargetLevel = targetLevel,
		MonsterKey = monsterKey,
		Template = template,
		MaxHealth = monsterDefinition.MaxHealth,
		Point = point,
		RuntimeRoot = runtimeRoot,
		PresentationId = presentationId,
		RiseDuration = presentation.Rise.TotalDuration,
		DemolishDuration = presentation.Demolish.TotalDuration,
		PreviousMonsterKey = record.MonsterKey,
		TemplateChanged = templateChanged,
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
	local plan, planReason = createLoadPlan(player, plot)
	if not plan then
		return result(false, planReason or "MonsterLoadPlanFailed", nil, 0)
	end

	local createdItems: { CreatedLoadItem } = {}
	local points = {}
	local function rollbackCreatedItems()
		for index = #createdItems, 1, -1 do
			local createdItem = createdItems[index]
			MonsterRosterCoordinator.RemoveForSpawnPoint(
				player,
				createdItem.Plan.SpawnPointId,
				createdItem.Plan.Point
			)
			local removed = MonsterIncubatorBuildCoordinator.Remove(
				plot,
				createdItem.Plan.SpawnPointId,
				createdItem.Incubator
			)
			if not removed.Succeeded then
				warn("回滚读档罐体失败：", removed.Reason)
			end
		end
	end
	for _, item in plan do
		local restoredIncubator = MonsterIncubatorBuildCoordinator.Restore(
			player,
			plot,
			item.SpawnPointId
		)
		if not restoredIncubator.Succeeded or not restoredIncubator.Incubator then
			rollbackCreatedItems()
			return result(
				false,
				(restoredIncubator.Reason or "MonsterIncubatorRestoreFailed")
					.. ":"
					.. item.SpawnPointId,
				nil,
				0
			)
		end
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
			local removed = MonsterIncubatorBuildCoordinator.Remove(
				plot,
				item.SpawnPointId,
				restoredIncubator.Incubator
			)
			if not removed.Succeeded then
				warn("怪兽读档失败后删除当前罐体失败：", removed.Reason)
			end
			rollbackCreatedItems()
			return result(false, (created.Reason or "MonsterCreateFailed") .. ":" .. item.SpawnPointId, nil, 0)
		end
		table.insert(createdItems, {
			Plan = item,
			Incubator = restoredIncubator.Incubator,
		})
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
	local builtIncubator = MonsterIncubatorBuildCoordinator.Build(
		player,
		plan.Plot,
		spawnPointId
	)
	if not builtIncubator.Succeeded or not builtIncubator.Incubator then
		return result(false, builtIncubator.Reason or "MonsterIncubatorBuildFailed", nil, nil)
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
		local removed = MonsterIncubatorBuildCoordinator.Remove(
			plan.Plot,
			spawnPointId,
			builtIncubator.Incubator
		)
		if not removed.Succeeded then
			warn("怪兽创建失败后删除罐体失败：", removed.Reason)
		end
		return result(false, created.Reason, created.Record, nil)
	end
	local presented = MonsterBuildPresentationPublisher.PublishAndWait({
		Kind = "MonsterBuild",
		OwnerUserId = player.UserId,
		SpawnPointId = spawnPointId,
		PresentationId = plan.PresentationId,
		MonsterKey = plan.MonsterKey,
	}, plan.RiseDuration, function()
		return player.Parent ~= Players
			or plan.Plot.Parent == nil
			or plan.Plot:GetAttribute("OwnerUserId") ~= player.UserId
	end)
	if not presented.Succeeded then
		local removedMonster = MonsterRosterCoordinator.RemoveForSpawnPoint(
			player,
			spawnPointId,
			plan.Point
		)
		if not removedMonster.Succeeded then
			warn("怪兽建造表现失败后删除怪兽失败：", removedMonster.Reason)
		end
		local removedIncubator = MonsterIncubatorBuildCoordinator.Remove(
			plan.Plot,
			spawnPointId,
			builtIncubator.Incubator
		)
		if not removedIncubator.Succeeded then
			warn("怪兽建造表现失败后删除罐体失败：", removedIncubator.Reason)
		end
		return result(
			false,
			presented.Reason or "MonsterBuildPresentationFailed",
			nil,
			nil
		)
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
	if plan.TemplateChanged then
		local presented = MonsterBuildPresentationPublisher.PublishAndWait({
			Kind = "MonsterUpgrade",
			OwnerUserId = player.UserId,
			SpawnPointId = spawnPointId,
			PresentationId = plan.PresentationId,
			PreviousMonsterKey = assert(plan.PreviousMonsterKey),
			MonsterKey = plan.MonsterKey,
		}, plan.DemolishDuration + plan.RiseDuration, nil)
		if not presented.Succeeded then
			-- 模型替换和保存身份已经提交；表现失败不能把成功升级误报为购买失败并退款。
			warn(string.format(
				"怪兽升级已提交，但拆除/建造表现失败：%s/%s (%s)",
				player.Name,
				spawnPointId,
				presented.Reason or "Unknown"
			))
		end
	end
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
	local incubatorRoot = plot and WorkspaceMonsterIncubatorAccess.GetRoot(plot)
	if incubatorRoot then
		incubatorRoot:Destroy()
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
