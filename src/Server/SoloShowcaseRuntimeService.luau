--[[
	职责：维护服务器启动时存在的固定单人演示场景。

	输入：Start/Reset 无玩家状态输入；攻击生命周期方法接收 HouseId、代次和伤害。
	输出：R1/R2 的可攻击区域、存活房屋快照、扣血结果，以及房屋/废墟运行时模型。
	内部算法：固定场景只生成 R1/R2 各 8 栋等级 1 房屋；伤害耗尽时直接替换为
	Ruin1，并按配置延迟恢复房屋；服务器无玩家时或演示重新开始时 Reset 回初始状态。
	不负责：玩家分配、玩家存档、攻击目标选择、动画、奖励或客户端相机。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingPlacement = require(ReplicatedStorage.Shared.Building.BuildingPlacement)
local CombatHealthBarProtocol = require(
	ReplicatedStorage.Shared.UI.CombatHealthBarProtocol
)
local IncomeHouseWorldUIProtocol = require(
	ReplicatedStorage.Shared.Building.IncomeHouseWorldUIProtocol
)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local RuntimeBuildingBounds = require(
	ReplicatedStorage.Shared.Building.RuntimeBuildingBounds
)
local ServerBuildingFactory = require(script.Parent.ServerBuildingFactory)
local PlotSceneVisibilityService = require(script.Parent.PlotSceneVisibilityService)
local TerritoryPointRules = require(
	ReplicatedStorage.Shared.Monster.TerritoryPointRules
)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local StructureHealthRules = require(
	ReplicatedStorage.Shared.Building.StructureHealthRules
)
local SoloMonsterAttackConfigs = require(
	ReplicatedStorage.Shared.Monster.SoloMonsterAttackConfigs
)

local SoloShowcaseRuntimeService = {}

local SHOWCASE_OWNER_USER_ID = -1
local BUILDINGS_ROOT_NAME = "Buildings"
local RUINS_ROOT_NAME = "Ruins"
local RUIN_TEMPLATE_PATH = "ReplicatedStorage/Buildings/Ruins/Ruin1"
local INITIAL_HOUSE_LEVEL = SoloMonsterAttackConfigs.InitialHouseLevel

local function getShowcaseHouseId(definition): string
	return "SoloShowcase-" .. definition.HouseId
end

type HouseState = {
	HouseId: string,
	RegionId: string,
	Level: number,
	CurrentHealth: number,
	MaxHealth: number,
	Generation: number,
	LifeState: "Alive" | "Destroyed",
	Model: Model?,
}

export type Territory = {
	ZoneId: string,
	BoundsId: string,
	CFrame: CFrame,
	Size: Vector3,
	AttackInProgress: boolean,
}

export type Area = {
	PlotName: string,
	AttackView: {
	CFrame: CFrame,
	Size: Vector3,
	},
	Territories: { Territory },
}

local definitions = {}
local definitionsByHouseId = {}
for _, definition in HouseCatalog.GetAll() do
	if table.find(SoloMonsterAttackConfigs.AttackableRegionIds, definition.RegionId) then
		table.insert(definitions, definition)
		definitionsByHouseId[getShowcaseHouseId(definition)] = definition
	end
end
table.sort(definitions, function(a, b)
	return a.HouseId < b.HouseId
end)

local statesByHouseId: { [string]: HouseState } = {}
local modelsByHouseId: { [string]: Model } = {}
local resetSerial = 0
local started = false

local function findPlot(): Model?
	local plot = workspace:FindFirstChild(SoloMonsterAttackConfigs.ShowcasePlotName)
	return if plot and plot:IsA("Model") then plot else nil
end

local function isContainer(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("Folder") or instance:IsA("Model"))
end

local function getOrCreateFolder(
	parent: Instance,
	name: string
): (Folder?, string?)
	local existing = parent:FindFirstChild(name)
	if existing then
		if not existing:IsA("Folder") then
			return nil, "Invalid" .. name .. "Folder"
		end
		return existing, nil
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder, nil
end

local function clearFolder(folder: Folder)
	for _, child in folder:GetChildren() do
		child:Destroy()
	end
end

local function getZone(plot: Model, regionId: string): Instance?
	local zones = plot:FindFirstChild("Zones")
	return if zones and zones:IsA("Folder") then zones:FindFirstChild(regionId) else nil
end

local function getBounds(plot: Model, regionId: string): { BasePart }
	local zone = getZone(plot, regionId)
	local bounds = zone and zone:FindFirstChild("Bounds")
	if not isContainer(bounds) then
		return {}
	end

	local result = {}
	for _, child in bounds:GetChildren() do
		if child:IsA("BasePart") and child.Size.X > 0 and child.Size.Z > 0 then
			table.insert(result, child)
		end
	end
	table.sort(result, function(a, b)
		return a.Name < b.Name
	end)
	return result
end

local function getSlot(plot: Model, definition): BasePart?
	local zone = definition and getZone(plot, definition.RegionId)
	local slots = zone and zone:FindFirstChild("Slots")
	local slot = slots and slots:FindFirstChild(definition.HouseId)
	return if slot and slot:IsA("BasePart") then slot else nil
end

local function resolveBuildingTemplate(definition): (Model?, string?)
	local root = InstancePath.Find(definition.ModelRoot)
	if not root then
		return nil, "BuildingTemplateRootUnavailable"
	end
	local group = root:FindFirstChild(definition.GroupName)
	local variant = if definition.VariantName
		then group and group:FindFirstChild(definition.VariantName)
		else group
	local template = variant and variant:FindFirstChild("level" .. INITIAL_HOUSE_LEVEL)
	if not template or not template:IsA("Model") then
		return nil, "BuildingTemplateUnavailable"
	end
	return template, nil
end

local function resolveRuinTemplate(): (Model?, string?)
	local template = InstancePath.Find(RUIN_TEMPLATE_PATH)
	if not template then
		return nil, "RuinTemplateUnavailable"
	end
	if not template:IsA("Model") then
		return nil, "RuinTemplateInvalid"
	end
	return template, nil
end

local function writeHouseAttributes(model: Model, state: HouseState)
	model:SetAttribute(
		IncomeHouseWorldUIProtocol.LifeStateAttributeName,
		state.LifeState
	)
	model:SetAttribute(
		IncomeHouseWorldUIProtocol.CurrentHealthAttributeName,
		state.CurrentHealth
	)
	model:SetAttribute(
		IncomeHouseWorldUIProtocol.MaxHealthAttributeName,
		state.MaxHealth
	)
	model:SetAttribute("BuildingHealthGeneration", state.Generation)
	model:SetAttribute(
		CombatHealthBarProtocol.HouseActiveAttackCountAttributeName,
		0
	)
	model:SetAttribute(IncomeHouseWorldUIProtocol.AutoIncomeAttributeName, false)
	model:SetAttribute(IncomeHouseWorldUIProtocol.IncomePerSecondAttributeName, 0)
	model:SetAttribute(IncomeHouseWorldUIProtocol.StoredMoneyAttributeName, 0)
	model:SetAttribute(IncomeHouseWorldUIProtocol.LastIncomeAtAttributeName, nil)
end

local function createBuilding(
	plot: Model,
	definition,
	state: HouseState,
	buildings: Folder
): (Model?, string?)
	local slot = getSlot(plot, definition)
	if not slot then
		return nil, "MissingBuildingSlot"
	end
	local template, templateReason = resolveBuildingTemplate(definition)
	if not template then
		return nil, templateReason or "BuildingTemplateUnavailable"
	end

	local targetPivot = BuildingPlacement.GetTargetPivot(template, slot.CFrame)
	local succeeded, modelOrError = pcall(
		ServerBuildingFactory.Create,
		template,
		targetPivot,
		buildings,
		{
			OwnerUserId = SHOWCASE_OWNER_USER_ID,
			HouseId = state.HouseId,
			ZoneId = definition.RegionId,
			SlotId = definition.HouseId,
			Level = state.Level,
		},
		false
	)
	if not succeeded then
		return nil, "BuildingCreateFailed:" .. tostring(modelOrError)
	end

	local model = modelOrError :: Model
	writeHouseAttributes(model, state)
	return model, nil
end

local function createRuin(
	plot: Model,
	definition,
	ruins: Folder
): (Model?, string?)
	local houseId = getShowcaseHouseId(definition)
	if ruins:FindFirstChild(houseId) then
		return nil, "RuinAlreadyExists"
	end
	local slot = getSlot(plot, definition)
	if not slot then
		return nil, "MissingBuildingSlot"
	end
	local template, templateReason = resolveRuinTemplate()
	if not template then
		return nil, templateReason or "RuinTemplateUnavailable"
	end

	local ruin = template:Clone()
	ruin.Name = houseId
	ruin:SetAttribute("RuinOwnerUserId", SHOWCASE_OWNER_USER_ID)
	ruin:SetAttribute("RuinHouseId", houseId)
	ruin:SetAttribute("RuinZoneId", definition.RegionId)
	ruin:SetAttribute("RuinSlotId", definition.HouseId)
	for _, descendant in ruin:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	local targetPivot = BuildingPlacement.GetTargetPivot(template, slot.CFrame)
	ruin:PivotTo(targetPivot)
	ruin.Parent = ruins
	return ruin, nil
end

local function getState(houseId: string): HouseState?
	return statesByHouseId[houseId]
end

local function getMaxHealth(_regionId: string): number?
	return SoloMonsterAttackConfigs.ShowcaseHouseMaxHealth
end

local function isAliveInRegion(regionId: string): boolean
	for _, definition in definitions do
		if definition.RegionId == regionId then
			local state = statesByHouseId[getShowcaseHouseId(definition)]
			if state and state.LifeState == "Alive" and state.Model and state.Model.Parent then
				return true
			end
		end
	end
	return false
end

local function buildArea(plot: Model): (Area?, string?)
	local view = plot:FindFirstChild("AttackViewBounds")
	if not view or not view:IsA("BasePart") then
		return nil, "SoloAttackViewUnavailable"
	end
	if view.Size.X <= 0 or view.Size.Y <= 0 or view.Size.Z <= 0 then
		return nil, "InvalidSoloAttackView"
	end

	local territories = {}
	for _, regionId in SoloMonsterAttackConfigs.AttackableRegionIds do
		if not isAliveInRegion(regionId) then
			continue
		end
		for _, bounds in getBounds(plot, regionId) do
			table.insert(territories, {
				ZoneId = regionId,
				BoundsId = bounds.Name,
				CFrame = bounds.CFrame,
				Size = bounds.Size,
				AttackInProgress = false,
			})
		end
	end
	if #territories == 0 then
		return nil, "SoloAttackRegionUnavailable"
	end

	return {
		PlotName = plot.Name,
		AttackView = {
			CFrame = view.CFrame,
			Size = view.Size,
		},
		Territories = territories,
	}, nil
end

local function retryRebuild(houseId: string, state: HouseState, serial: number)
	if serial ~= resetSerial or statesByHouseId[houseId] ~= state then
		return
	end
	if state.LifeState ~= "Destroyed" then
		return
	end
	task.delay(2, function()
		if serial == resetSerial and statesByHouseId[houseId] == state then
			local plot = findPlot()
			if plot then
				local runtime = plot:FindFirstChild("Runtime")
				local buildings = runtime and runtime:FindFirstChild(BUILDINGS_ROOT_NAME)
				if buildings and buildings:IsA("Folder") then
					local definition = definitionsByHouseId[houseId]
					if definition then
						local model = createBuilding(plot, definition, state, buildings)
						if model then
							state.Generation += 1
							state.CurrentHealth = state.MaxHealth
							state.LifeState = "Alive"
							state.Model = model
							modelsByHouseId[houseId] = model
							writeHouseAttributes(model, state)
							local ruins = runtime:FindFirstChild(RUINS_ROOT_NAME)
							local ruin = ruins and ruins:FindFirstChild(houseId)
							if ruin then
								ruin:Destroy()
							end
							return
						end
					end
				end
			end
			retryRebuild(houseId, state, serial)
		end
	end)
end

local function scheduleRebuild(houseId: string, state: HouseState)
	local serial = resetSerial
	task.delay(SoloMonsterAttackConfigs.RebuildDelaySeconds, function()
		if serial ~= resetSerial or statesByHouseId[houseId] ~= state then
			return
		end
		if state.LifeState ~= "Destroyed" then
			return
		end

		local plot = findPlot()
		local runtime = plot and plot:FindFirstChild("Runtime")
		local buildings = runtime and runtime:FindFirstChild(BUILDINGS_ROOT_NAME)
		local definition = definitionsByHouseId[houseId]
		if not plot or not buildings or not buildings:IsA("Folder") or not definition then
			retryRebuild(houseId, state, serial)
			return
		end

		local model = createBuilding(plot, definition, state, buildings)
		if not model then
			retryRebuild(houseId, state, serial)
			return
		end

		state.Generation += 1
		state.CurrentHealth = state.MaxHealth
		state.LifeState = "Alive"
		state.Model = model
		modelsByHouseId[houseId] = model
		writeHouseAttributes(model, state)

		local ruins = runtime:FindFirstChild(RUINS_ROOT_NAME)
		local ruin = ruins and ruins:FindFirstChild(houseId)
		if ruin then
			ruin:Destroy()
		end
	end)
end

function SoloShowcaseRuntimeService.Start(): (boolean, string?)
	if started then
		return true, nil
	end
	started = true

	local plot = findPlot()
	if not plot then
		warn(
			"找不到固定单人演示场景：Workspace/"
				.. SoloMonsterAttackConfigs.ShowcasePlotName
		)
		return false, "SoloShowcasePlotUnavailable"
	end
	local ruinTemplate, ruinReason = resolveRuinTemplate()
	if not ruinTemplate then
		warn("固定单人演示场景缺少废墟模板：", ruinReason or "Unknown")
		return false, ruinReason or "RuinTemplateUnavailable"
	end

	local resetSucceeded, resetReason = SoloShowcaseRuntimeService.Reset()
	if not resetSucceeded then
		warn("固定单人演示场景初始化失败：", resetReason)
	end

	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if #Players:GetPlayers() == 0 then
				local succeeded, reason = SoloShowcaseRuntimeService.Reset()
				if not succeeded then
					warn("无人时恢复单人演示场景失败：", reason)
				end
			end
		end)
	end)

	return resetSucceeded, resetReason
end

function SoloShowcaseRuntimeService.Reset(): (boolean, string?)
	local plot = findPlot()
	if not plot then
		return false, "SoloShowcasePlotUnavailable"
	end

	local runtime = plot:FindFirstChild("Runtime")
	if not runtime or not runtime:IsA("Folder") then
		return false, "MissingPlotRuntime"
	end
	local buildings, buildingsReason = getOrCreateFolder(runtime, BUILDINGS_ROOT_NAME)
	if not buildings then
		return false, buildingsReason or "MissingBuildingsRuntime"
	end
	local ruins, ruinsReason = getOrCreateFolder(runtime, RUINS_ROOT_NAME)
	if not ruins then
		return false, ruinsReason or "MissingRuinsRuntime"
	end

	resetSerial += 1
	statesByHouseId = {}
	modelsByHouseId = {}
	clearFolder(buildings)
	clearFolder(ruins)
	PlotSceneVisibilityService.ApplyDefault(plot)

	local failedHouseId: string? = nil
	for _, definition in definitions do
		local maxHealth = getMaxHealth(definition.RegionId)
		if not maxHealth then
			failedHouseId = getShowcaseHouseId(definition)
			warn("演示房屋缺少耐久配置：", failedHouseId)
			continue
		end
		local houseId = getShowcaseHouseId(definition)
		local state: HouseState = {
			HouseId = houseId,
			RegionId = definition.RegionId,
			Level = INITIAL_HOUSE_LEVEL,
			CurrentHealth = maxHealth,
			MaxHealth = maxHealth,
			Generation = 1,
			LifeState = "Alive",
			Model = nil,
		}
		statesByHouseId[houseId] = state
		local model, modelReason = createBuilding(plot, definition, state, buildings)
		if not model then
			failedHouseId = houseId
			warn("演示房屋创建失败：", houseId, modelReason or "Unknown")
			continue
		end
		state.Model = model
		modelsByHouseId[houseId] = model
	end

	if failedHouseId then
		return false, "ShowcaseHouseUnavailable:" .. failedHouseId
	end
	return true, nil
end

function SoloShowcaseRuntimeService.GetPlot(): Model?
	return findPlot()
end

function SoloShowcaseRuntimeService.GetArea(): (Area?, string?)
	local plot = findPlot()
	if not plot then
		return nil, "SoloShowcasePlotUnavailable"
	end
	return buildArea(plot)
end

function SoloShowcaseRuntimeService.ResolveRegion(
	plotName: string?,
	entryPoint: Vector3
): (string?, string?)
	local plot = findPlot()
	if not plot or (plotName ~= nil and plotName ~= "" and plot.Name ~= plotName) then
		return nil, "SoloShowcasePlotUnavailable"
	end
	local area, areaReason = buildArea(plot)
	if not area then
		return nil, areaReason or "SoloAttackRegionUnavailable"
	end
	for _, territory in area.Territories do
		local pointCheck = TerritoryPointRules.Check(
			territory.CFrame,
			territory.Size,
			entryPoint
		)
		if pointCheck.Allowed then
			return territory.ZoneId, nil
		end
	end
	return nil, "SoloAttackRegionUnavailable"
end

function SoloShowcaseRuntimeService.ListAliveTargets(): { any }
	local targets = {}
	for _, definition in definitions do
		local state = statesByHouseId[getShowcaseHouseId(definition)]
		local model = state and state.Model
		if not state or state.LifeState ~= "Alive" or not model or not model.Parent then
			continue
		end
		local bounds = RuntimeBuildingBounds.Resolve(model)
		if bounds then
			table.insert(targets, {
				HouseId = state.HouseId,
				RegionId = definition.RegionId,
				CFrame = bounds.CFrame,
				Size = bounds.Size,
				HealthGeneration = state.Generation,
				CurrentHealth = state.CurrentHealth,
				MaxHealth = state.MaxHealth,
			})
		end
	end
	return targets
end

function SoloShowcaseRuntimeService.ResolveAliveTarget(houseId: string): (any?, string?)
	local state = getState(houseId)
	local model = state and state.Model
	if not state then
		return nil, "UnknownHouse"
	end
	if state.LifeState ~= "Alive" then
		return nil, "HouseNotAlive"
	end
	if not model or not model.Parent then
		return nil, "RuntimeBuildingUnavailable"
	end
	local bounds, boundsReason = RuntimeBuildingBounds.Resolve(model)
	if not bounds then
		return nil, boundsReason or "RuntimeBuildingBoundsUnavailable"
	end
	return {
		HouseId = houseId,
		RegionId = state.RegionId,
		CFrame = bounds.CFrame,
		Size = bounds.Size,
		HealthGeneration = state.Generation,
		CurrentHealth = state.CurrentHealth,
		MaxHealth = state.MaxHealth,
	}, nil
end

function SoloShowcaseRuntimeService.ApplyDamage(
	houseId: string,
	expectedGeneration: number,
	damage: number
)
	local state = getState(houseId)
	if not state then
		return {
			Accepted = false,
			Reason = "UnknownHouse",
			HouseId = houseId,
			Level = nil,
			Generation = nil,
			PreviousHealth = nil,
			CurrentHealth = nil,
			MaxHealth = nil,
			DamageApplied = 0,
			Depleted = false,
		}
	end
	if state.LifeState ~= "Alive" then
		return {
			Accepted = false,
			Reason = "HouseNotAlive",
			HouseId = houseId,
			Level = state.Level,
			Generation = state.Generation,
			PreviousHealth = state.CurrentHealth,
			CurrentHealth = state.CurrentHealth,
			MaxHealth = state.MaxHealth,
			DamageApplied = 0,
			Depleted = state.CurrentHealth == 0,
		}
	end
	if expectedGeneration ~= state.Generation then
		return {
			Accepted = false,
			Reason = "StaleHealthGeneration",
			HouseId = houseId,
			Level = state.Level,
			Generation = state.Generation,
			PreviousHealth = state.CurrentHealth,
			CurrentHealth = state.CurrentHealth,
			MaxHealth = state.MaxHealth,
			DamageApplied = 0,
			Depleted = false,
		}
	end

	local applied = StructureHealthRules.ApplyDamage(
		state.CurrentHealth,
		state.MaxHealth,
		damage
	)
	if applied.Accepted then
		state.CurrentHealth = applied.RemainingHealth
		if state.Model then
			writeHouseAttributes(state.Model, state)
		end
	end
	return {
		Accepted = applied.Accepted,
		Reason = applied.Reason,
		HouseId = houseId,
		Level = state.Level,
		Generation = state.Generation,
		PreviousHealth = applied.PreviousHealth,
		CurrentHealth = applied.RemainingHealth,
		MaxHealth = applied.MaxHealth,
		DamageApplied = applied.DamageApplied,
		Depleted = applied.Depleted,
	}
end

function SoloShowcaseRuntimeService.RollbackDamage(
	houseId: string,
	expectedGeneration: number,
	previousHealth: number
): boolean
	local state = getState(houseId)
	if not state
		or state.LifeState ~= "Alive"
		or state.Generation ~= expectedGeneration
		or state.CurrentHealth ~= 0
		or previousHealth <= 0
		or previousHealth > state.MaxHealth
	then
		return false
	end
	state.CurrentHealth = previousHealth
	if state.Model then
		writeHouseAttributes(state.Model, state)
	end
	return true
end

function SoloShowcaseRuntimeService.PrepareDestroy(houseId: string): (boolean, string?)
	local target, reason = SoloShowcaseRuntimeService.ResolveAliveTarget(houseId)
	return target ~= nil, reason
end

function SoloShowcaseRuntimeService.Destroy(houseId: string): (boolean, string?)
	local state = getState(houseId)
	local definition = definitionsByHouseId[houseId]
	local model = state and state.Model
	if not state or not definition then
		return false, "UnknownHouse"
	end
	if state.LifeState ~= "Alive" then
		return false, "HouseNotAlive"
	end
	if not model or not model.Parent then
		return false, "RuntimeBuildingUnavailable"
	end

	local plot = findPlot()
	local runtime = plot and plot:FindFirstChild("Runtime")
	local ruins = runtime and runtime:FindFirstChild(RUINS_ROOT_NAME)
	if not plot or not ruins or not ruins:IsA("Folder") then
		return false, "MissingRuinsRuntime"
	end
	local ruin, ruinReason = createRuin(plot, definition, ruins)
	if not ruin then
		return false, ruinReason or "RuinCreateFailed"
	end

	model:Destroy()
	state.Model = nil
	modelsByHouseId[houseId] = nil
	state.LifeState = "Destroyed"
	state.CurrentHealth = 0
	scheduleRebuild(houseId, state)
	return true, nil
end

return SoloShowcaseRuntimeService
