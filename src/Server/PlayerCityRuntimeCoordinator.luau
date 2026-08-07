--[[
	职责：
	- 把玩家已解锁 Zone 中处于 Alive 的房屋恢复为服务器权威建筑。
	- 维护 Player + HouseId 到运行时 Model 的查询入口。

	输入：
	- Load：已经进入服务器并分配 Plot 的 Player。
	- RefreshZone：Player、需要重新生成的 ZoneId，以及可选的建造表现预隐藏标记。
	- RestoreBuilding：Player、当前处于 Destroyed 的 HouseId，以及可选的建造表现预隐藏标记。
	- RemoveBuilding：Player、HouseId，以及可选的预期 Model。
	- Unload / ResolveBuilding / ListBuildings：Player；查询额外接收 HouseId。

	输出：
	- 建筑生成在 Plot/Runtime/Buildings/<HouseId>。
	- Load 返回成功状态、稳定失败原因和加载数量。
	- RefreshZone 只替换目标 Zone，不重建其他 Zone；可让新模型以隐藏态进入运行时树。
	- RestoreBuilding 使用 Zone 当前最新等级，只恢复目标单栋建筑；可让新模型预隐藏。
	- RemoveBuilding 只移除目标玩家的一栋当前权威建筑。
	- ResolveBuilding / ListBuildings 返回服务器当前运行时建筑。

	内部算法：
	- 读取 Plot 和已解锁 IncomeBuilding Slot。
	- 遍历 HouseCatalog，只为 LifeState == Alive 的房屋解析模板和位置。
	- 完成全部输入校验后清理旧建筑，再批量创建并写入运行时索引。

	不负责：
	- 不修改 Zone 或 HouseState，不播放建造动画，不处理攻击和收入。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutomaticIncomeRatePresentationService = require(
	script.Parent.AutomaticIncomeRatePresentationService
)
local HouseRuinRuntimeService = require(script.Parent.HouseRuinRuntimeService)
local HouseStateService = require(script.Parent.HouseStateService)
local HouseWorldUIPresentationService = require(script.Parent.HouseWorldUIPresentationService)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerRuntimeLoadReporter = require(
	script.Parent.Analytics.PlayerRuntimeLoadReporter
)
local PlayerBuildingRuntimeRegistry = require(script.Parent.PlayerBuildingRuntimeRegistry)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local ServerBuildingFactory = require(script.Parent.ServerBuildingFactory)
local WorkspacePlayerWorldAccess = require(script.Parent.WorkspacePlayerWorldAccess)
local ZoneStateService = require(script.Parent.ZoneStateService)
local BuildingPlacement = require(ReplicatedStorage.Shared.Building.BuildingPlacement)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local IncomeBuildingProgressionRules = require(
	ReplicatedStorage.Shared.Building.IncomeBuildingProgressionRules
)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)

local PlayerCityRuntimeCoordinator = {}

export type LoadResult = {
	Succeeded: boolean,
	Reason: string?,
	Plot: Model?,
	LoadedCount: number,
}

export type RemoveResult = {
	Succeeded: boolean,
	Reason: string?,
	RemovedModel: Model?,
}

export type RestoreResult = {
	Succeeded: boolean,
	Reason: string?,
	Model: Model?,
}

type BuildPlanItem = {
	HouseId: string,
	ZoneId: string,
	SlotId: string,
	Template: Model,
	TargetPivot: CFrame,
	Level: number,
}

local BUILDINGS_ROOT_NAME = "Buildings"
local INCOME_SLOT_KIND = "IncomeBuilding"
local loadedPlots: { [Player]: Model } = setmetatable({}, { __mode = "k" })
local started = false

local function result(
	succeeded: boolean,
	reason: string?,
	plot: Model?,
	loadedCount: number
): LoadResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		Plot = plot,
		LoadedCount = loadedCount,
	}
end

local function getBuildingsRoot(plot: Model): (Folder?, string?)
	local runtime = plot:FindFirstChild("Runtime")
	if not runtime or not runtime:IsA("Folder") then
		return nil, "MissingPlotRuntime"
	end

	local existing = runtime:FindFirstChild(BUILDINGS_ROOT_NAME)
	if existing then
		if not existing:IsA("Folder") then
			return nil, "InvalidBuildingsRuntime"
		end
		return existing, nil
	end

	local folder = Instance.new("Folder")
	folder.Name = BUILDINGS_ROOT_NAME
	folder.Parent = runtime
	return folder, nil
end

local function resolveTemplate(
	modelRootPath: string,
	groupName: string,
	variantName: string?,
	level: number,
	rootCache: { [string]: Instance }
): (Model?, string?)
	local root = rootCache[modelRootPath]
	if not root then
		local found, value = pcall(InstancePath.Get, modelRootPath)
		if not found then
			warn(string.format("建筑模板根目录不可用：%s (%s)", modelRootPath, tostring(value)))
			return nil, "TemplateRootUnavailable"
		end
		root = value :: Instance
		rootCache[modelRootPath] = root
	end

	local group = root:FindFirstChild(groupName)
	local variant = if variantName then group and group:FindFirstChild(variantName) else group
	local template = variant and variant:FindFirstChild("level" .. level)
	if not template or not template:IsA("Model") then
		return nil, "BuildingTemplateUnavailable"
	end
	return template, nil
end

local function createBuildPlan(
	player: Player,
	onlyZoneId: string?
): ({ BuildPlanItem }?, string?)
	local slotsById = {}
	for _, slot in WorkspacePlayerWorldAccess.Slots.ListUnlockedSlots(player, INCOME_SLOT_KIND) do
		if slotsById[slot.SlotId] then
			return nil, "DuplicateRuntimeSlot"
		end
		slotsById[slot.SlotId] = slot
	end

	local rootCache: { [string]: Instance } = {}
	local plan = {}
	for _, definition in HouseCatalog.GetAll() do
		if onlyZoneId and definition.RegionId ~= onlyZoneId then
			continue
		end
		if not ZoneStateService.GetUnlocked(player, definition.RegionId) then
			continue
		end

		local state = HouseStateService.Get(player, definition.HouseId)
		if state.LifeState == "Unbuilt"
			or state.LifeState == "Destroyed"
			or state.LifeState == "Rebuilding"
		then
			continue
		end
		if state.LifeState ~= "Alive" then
			return nil, "InvalidHouseLifeState:" .. definition.HouseId
		end

		local slot = slotsById[definition.HouseId]
		if not slot then
			return nil, "MissingBuildingSlot:" .. definition.HouseId
		end
		if slot.ZoneId ~= definition.RegionId then
			return nil, "BuildingSlotZoneMismatch:" .. definition.HouseId
		end

		local regionLevel = ZoneStateService.GetLevel(player, definition.RegionId)
		if regionLevel <= 0 then
			return nil, "AliveHouseInUnbuiltZone:" .. definition.HouseId
		end
		local modelLevel = IncomeBuildingProgressionRules.ResolveModelLevel(
			regionLevel,
			definition.BuildAtRegionLevel,
			definition.RegionLevelsPerModelLevel,
			definition.MaxModelLevel
		)
		if not modelLevel then
			return nil, "AliveHouseBeforeBuildLevel:" .. definition.HouseId
		end

		local template, templateReason = resolveTemplate(
			definition.ModelRoot,
			definition.GroupName,
			definition.VariantName,
			modelLevel,
			rootCache
		)
		if not template then
			return nil, (templateReason or "BuildingTemplateUnavailable") .. ":" .. definition.HouseId
		end

		table.insert(plan, {
			HouseId = definition.HouseId,
			ZoneId = slot.ZoneId,
			SlotId = slot.SlotId,
			Template = template,
			TargetPivot = BuildingPlacement.GetTargetPivot(template, slot.Point.CFrame),
			Level = regionLevel,
		})
	end
	return plan, nil
end

local function createRestorePlan(
	player: Player,
	houseId: string
): (BuildPlanItem?, string?)
	local definition = HouseCatalog.Get(houseId)
	if not definition then
		return nil, "UnknownHouse"
	end
	if not ZoneStateService.GetUnlocked(player, definition.RegionId) then
		return nil, "HouseZoneLocked"
	end
	if HouseStateService.Get(player, houseId).LifeState ~= "Destroyed" then
		return nil, "HouseNotDestroyed"
	end

	local targetSlot = nil
	for _, slot in WorkspacePlayerWorldAccess.Slots.ListUnlockedSlots(
		player,
		INCOME_SLOT_KIND
	) do
		if slot.SlotId == houseId then
			targetSlot = slot
			break
		end
	end
	if not targetSlot then
		return nil, "MissingBuildingSlot"
	end
	if targetSlot.ZoneId ~= definition.RegionId then
		return nil, "BuildingSlotZoneMismatch"
	end

	local regionLevel = ZoneStateService.GetLevel(player, definition.RegionId)
	if regionLevel <= 0 then
		return nil, "HouseInUnbuiltZone"
	end
	local modelLevel = IncomeBuildingProgressionRules.ResolveModelLevel(
		regionLevel,
		definition.BuildAtRegionLevel,
		definition.RegionLevelsPerModelLevel,
		definition.MaxModelLevel
	)
	if not modelLevel then
		return nil, "HouseBeforeBuildLevel"
	end
	local template, templateReason = resolveTemplate(
		definition.ModelRoot,
		definition.GroupName,
		definition.VariantName,
		modelLevel,
		{}
	)
	if not template then
		return nil, templateReason or "BuildingTemplateUnavailable"
	end
	return {
		HouseId = houseId,
		ZoneId = definition.RegionId,
		SlotId = targetSlot.SlotId,
		Template = template,
		TargetPivot = BuildingPlacement.GetTargetPivot(template, targetSlot.Point.CFrame),
		Level = regionLevel,
	}, nil
end

local function destroyIndexedBuildings(player: Player)
	for _, model in PlayerBuildingRuntimeRegistry.Clear(player) do
		if model.Parent then
			model:Destroy()
		end
	end
end

local function clearFolder(folder: Folder)
	for _, child in folder:GetChildren() do
		child:Destroy()
	end
end

local function clearZoneBuildings(player: Player, folder: Folder, zoneId: string)
	for houseId, model in PlayerBuildingRuntimeRegistry.List(player) do
		local definition = HouseCatalog.Get(houseId)
		if (definition and definition.RegionId == zoneId)
			or model:GetAttribute("BuildingZoneId") == zoneId
		then
			PlayerBuildingRuntimeRegistry.Remove(player, houseId)
			if model.Parent then
				model:Destroy()
			end
		end
	end

	-- 清理可能未写入索引的同 Zone 残留，其他 Zone 不受影响。
	for _, child in folder:GetChildren() do
		if child:GetAttribute("BuildingZoneId") == zoneId then
			child:Destroy()
		end
	end
end

local function refreshWorldUI(player: Player, houseId: string, model: Model)
	local called, refreshed, reason = pcall(
		HouseWorldUIPresentationService.Refresh,
		player,
		houseId,
		model
	)
	if not called then
		warn(string.format("刷新房屋世界 UI 状态异常：%s/%s (%s)", player.Name, houseId, tostring(refreshed)))
	elseif not refreshed then
		warn(string.format("刷新房屋世界 UI 状态失败：%s/%s (%s)", player.Name, houseId, reason or "Unknown"))
	end
end

local function createBuildings(
	player: Player,
	buildingsRoot: Folder,
	plan: { BuildPlanItem },
	hideForPresentation: boolean
): (number, string?)
	local createdCount = 0
	for _, item in plan do
		local created, modelOrError = pcall(
			ServerBuildingFactory.Create,
			item.Template,
			item.TargetPivot,
			buildingsRoot,
			{
				OwnerUserId = player.UserId,
				HouseId = item.HouseId,
				ZoneId = item.ZoneId,
				SlotId = item.SlotId,
				Level = item.Level,
			},
			hideForPresentation
		)
		if not created then
			warn(string.format("创建服务器建筑失败：%s (%s)", item.HouseId, tostring(modelOrError)))
			return createdCount, "BuildingCreateFailed:" .. item.HouseId
		end

		local model = modelOrError :: Model
		local previous = PlayerBuildingRuntimeRegistry.Set(player, item.HouseId, model)
		if previous and previous.Parent then
			previous:Destroy()
		end
		refreshWorldUI(player, item.HouseId, model)
		createdCount += 1
	end
	return createdCount, nil
end

-- 输入：在线 player、当前 Destroyed 的 houseId，以及可选的建造表现预隐藏标记。
-- 输出：按 Zone 当前最新等级创建并登记的一栋服务器权威建筑。
-- 内部算法：校验 Plot/Slot/状态/模板后只 Clone 单栋；可在 Parent 前预隐藏，不刷新同 Zone 其他建筑。
function PlayerCityRuntimeCoordinator.RestoreBuilding(
	player: Player,
	houseId: string,
	hideForPresentation: boolean?
): RestoreResult
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	assert(
		hideForPresentation == nil or type(hideForPresentation) == "boolean",
		"hideForPresentation 必须是 boolean 或 nil"
	)
	if player.Parent ~= Players then
		return { Succeeded = false, Reason = "PlayerUnavailable", Model = nil }
	end
	if PlayerBuildingRuntimeRegistry.Get(player, houseId) then
		return { Succeeded = false, Reason = "RuntimeBuildingAlreadyExists", Model = nil }
	end

	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return { Succeeded = false, Reason = plotReason or "PlayerHasNoPlot", Model = nil }
	end
	local buildingsRoot, runtimeReason = getBuildingsRoot(plot)
	if not buildingsRoot then
		return { Succeeded = false, Reason = runtimeReason or "MissingBuildingsRuntime", Model = nil }
	end
	local plan, planReason = createRestorePlan(player, houseId)
	if not plan then
		return { Succeeded = false, Reason = planReason or "RestorePlanFailed", Model = nil }
	end

	local created, modelOrError = pcall(
		ServerBuildingFactory.Create,
		plan.Template,
		plan.TargetPivot,
		buildingsRoot,
		{
			OwnerUserId = player.UserId,
			HouseId = plan.HouseId,
			ZoneId = plan.ZoneId,
			SlotId = plan.SlotId,
			Level = plan.Level,
		},
		hideForPresentation
	)
	if not created then
		warn(string.format("恢复服务器建筑失败：%s (%s)", houseId, tostring(modelOrError)))
		return { Succeeded = false, Reason = "BuildingCreateFailed", Model = nil }
	end

	local model = modelOrError :: Model
	local previous = PlayerBuildingRuntimeRegistry.Set(player, houseId, model)
	if previous then
		PlayerBuildingRuntimeRegistry.Set(player, houseId, previous)
		model:Destroy()
		return { Succeeded = false, Reason = "RuntimeBuildingChanged", Model = nil }
	end
	loadedPlots[player] = plot
	refreshWorldUI(player, houseId, model)
	return { Succeeded = true, Reason = nil, Model = model }
end

function PlayerCityRuntimeCoordinator.Load(player: Player): LoadResult
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local ready, readyReason = PlayerDataReadyService.Wait(player)
	if not ready then
		return result(false, readyReason or "PlayerDataUnavailable", nil, 0)
	end
	if player.Parent ~= Players then
		return result(false, "PlayerUnavailable", nil, 0)
	end
	AutomaticIncomeRatePresentationService.Refresh(player)

	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return result(false, plotReason or "PlayerHasNoPlot", nil, 0)
	end
	HouseRuinRuntimeService.ClearPlot(plot)
	local buildingsRoot, runtimeReason = getBuildingsRoot(plot)
	if not buildingsRoot then
		return result(false, runtimeReason or "MissingBuildingsRuntime", plot, 0)
	end

	local plan, planReason = createBuildPlan(player, nil)
	if not plan then
		return result(false, planReason or "CityBuildPlanFailed", plot, 0)
	end

	destroyIndexedBuildings(player)
	clearFolder(buildingsRoot)
	loadedPlots[player] = plot

	local createdCount, createReason = createBuildings(player, buildingsRoot, plan, false)
	if createReason then
		destroyIndexedBuildings(player)
		clearFolder(buildingsRoot)
		loadedPlots[player] = nil
		return result(false, createReason, plot, 0)
	end

	return result(true, nil, plot, createdCount)
end

function PlayerCityRuntimeCoordinator.RefreshZone(
	player: Player,
	zoneId: string,
	hideForPresentation: boolean?
): LoadResult
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(zoneId) == "string" and zoneId ~= "", "zoneId 必须是非空字符串")
	assert(
		hideForPresentation == nil or type(hideForPresentation) == "boolean",
		"hideForPresentation 必须是 boolean 或 nil"
	)
	if player.Parent ~= Players then
		return result(false, "PlayerUnavailable", nil, 0)
	end

	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return result(false, plotReason or "PlayerHasNoPlot", nil, 0)
	end
	local buildingsRoot, runtimeReason = getBuildingsRoot(plot)
	if not buildingsRoot then
		return result(false, runtimeReason or "MissingBuildingsRuntime", plot, 0)
	end

	local plan, planReason = createBuildPlan(player, zoneId)
	if not plan then
		return result(false, planReason or "CityBuildPlanFailed", plot, 0)
	end

	clearZoneBuildings(player, buildingsRoot, zoneId)
	loadedPlots[player] = plot
	local createdCount, createReason = createBuildings(
		player,
		buildingsRoot,
		plan,
		hideForPresentation == true
	)
	if createReason then
		clearZoneBuildings(player, buildingsRoot, zoneId)
		return result(false, createReason, plot, 0)
	end
	return result(true, nil, plot, createdCount)
end

function PlayerCityRuntimeCoordinator.RemoveBuilding(
	player: Player,
	houseId: string,
	expectedModel: Model?
): RemoveResult
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	assert(
		expectedModel == nil
			or (typeof(expectedModel) == "Instance" and expectedModel:IsA("Model")),
		"expectedModel 必须是 Model 或 nil"
	)

	local current = PlayerBuildingRuntimeRegistry.Get(player, houseId)
	if not current then
		return {
			Succeeded = false,
			Reason = "RuntimeBuildingUnavailable",
			RemovedModel = nil,
		}
	end
	if expectedModel and current ~= expectedModel then
		return {
			Succeeded = false,
			Reason = "RuntimeBuildingChanged",
			RemovedModel = nil,
		}
	end

	local removed = PlayerBuildingRuntimeRegistry.Remove(player, houseId)
	if removed ~= current then
		return {
			Succeeded = false,
			Reason = "RuntimeBuildingRemoveRejected",
			RemovedModel = nil,
		}
	end
	if removed.Parent then
		removed:Destroy()
	end
	return {
		Succeeded = true,
		Reason = nil,
		RemovedModel = removed,
	}
end

function PlayerCityRuntimeCoordinator.Unload(player: Player): number
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local removed = PlayerBuildingRuntimeRegistry.List(player)
	local removedCount = 0
	for _ in pairs(removed) do
		removedCount += 1
	end
	destroyIndexedBuildings(player)

	local plot = loadedPlots[player]
	loadedPlots[player] = nil
	local runtime = plot and plot:FindFirstChild("Runtime")
	local buildings = runtime and runtime:FindFirstChild(BUILDINGS_ROOT_NAME)
	if buildings and buildings:IsA("Folder") then
		-- 客户端只订阅一次固定 Buildings Folder；重生/显式重载必须保留目录身份。
		clearFolder(buildings)
	end
	if plot then
		HouseRuinRuntimeService.ClearPlot(plot)
	end
	return removedCount
end

function PlayerCityRuntimeCoordinator.ResolveBuilding(
	player: Player,
	houseId: string
): Model?
	return PlayerBuildingRuntimeRegistry.Get(player, houseId)
end

function PlayerCityRuntimeCoordinator.ListBuildings(player: Player): { [string]: Model }
	return PlayerBuildingRuntimeRegistry.List(player)
end

local function loadAndWarn(player: Player)
	local loadResult = PlayerCityRuntimeCoordinator.Load(player)
	PlayerRuntimeLoadReporter.Report(
		player,
		"City",
		loadResult.Succeeded,
		loadResult.Reason
	)
	if not loadResult.Succeeded then
		warn(string.format("加载玩家 %s 城市失败：%s", player.Name, loadResult.Reason or "Unknown"))
	end
end

function PlayerCityRuntimeCoordinator.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(function(player)
		task.defer(loadAndWarn, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		PlayerCityRuntimeCoordinator.Unload(player)
	end)

	for _, player in Players:GetPlayers() do
		loadAndWarn(player)
	end
end

return PlayerCityRuntimeCoordinator
