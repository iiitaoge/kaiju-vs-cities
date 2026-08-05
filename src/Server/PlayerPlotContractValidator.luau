--[[
	职责：组合核心、产钱区和怪兽区规则，验证八人 PlayerPlots 场景合同及体验容量。
	输入：ValidatePlot 接收单个 Plot；ValidateAll/AssertAll 读取 Workspace/PlayerPlots、Players.MaxPlayers 和运行环境。
	输出：错误列表，或包含 Valid/Errors/Warnings/PlotCount/RequiredMaxPlayers/MaxPlayers/CapacityValid 的总报告。
	内部算法：复用唯一直接子级与锚定零件小模块，再组合现有 Income 验证器和怪兽目录配置。
	不负责：逐后代比较 Plot01 克隆、修改场景、分配玩家、生成 Runtime 或更改体验设置。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnchoredPartRules = require(script.Parent.AnchoredPartRules)
local IncomePlotContractValidator = require(script.Parent.IncomePlotContractValidator)
local UniqueNamedChildAccess = require(script.Parent.UniqueNamedChildAccess)
local MonsterIncubatorConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorConfigs
)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local RebirthProgressionConfigs = require(
	ReplicatedStorage.Shared.Progression.RebirthProgressionConfigs
)
local EightPlayerCapacityAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.EightPlayerCapacityAcceptanceProtocol
)

local PlayerPlotContractValidator = {}

local EXPECTED_PLOT_COUNT = EightPlayerCapacityAcceptanceProtocol.RequiredPlayerCount

local function validateCapacity(): (boolean, string)
	local actual = Players.MaxPlayers
	if RunService:IsStudio() then
		return actual >= EXPECTED_PLOT_COUNT, string.format(
			"Studio 本地测试容量必须不少于 %d，当前为 %d",
			EXPECTED_PLOT_COUNT,
			actual
		)
	end
	return actual == EXPECTED_PLOT_COUNT, string.format(
		"线上运行时 MaxPlayers 报告值应为 %d，当前为 %d；以 Creator Dashboard 的访客人数上限为准",
		EXPECTED_PLOT_COUNT,
		actual
	)
end

local function add(errors: { string }, condition: boolean, message: string)
	if not condition then
		table.insert(errors, message)
	end
end

local function uniqueChild(
	errors: { string },
	parent: Instance,
	name: string,
	expectedClass: string
): Instance?
	local child, duplicated = UniqueNamedChildAccess.Find(parent, name)
	if duplicated then
		table.insert(errors, parent:GetFullName() .. "/" .. name .. " 存在同名重复项")
		return nil
	end
	add(
		errors,
		child ~= nil and child:IsA(expectedClass),
		string.format("%s/%s 必须是 %s", parent:GetFullName(), name, expectedClass)
	)
	return if child and child:IsA(expectedClass) then child else nil
end

local function anchoredPart(
	errors: { string },
	parent: Instance,
	name: string
): BasePart?
	local child = uniqueChild(errors, parent, name, "BasePart")
	if not child then
		return nil
	end
	add(
		errors,
		AnchoredPartRules.HasOnlyAnchoredParts(child),
		child:GetFullName() .. " 必须 Anchored"
	)
	return child :: BasePart
end

local function uniqueContainer(errors: { string }, parent: Instance, name: string): Instance?
	local child, duplicated = UniqueNamedChildAccess.Find(parent, name)
	if duplicated then
		table.insert(errors, parent:GetFullName() .. "/" .. name .. " 存在同名重复项")
		return nil
	end
	local valid = child ~= nil and (child:IsA("Folder") or child:IsA("Model"))
	add(errors, valid, parent:GetFullName() .. "/" .. name .. " 必须是 Folder 或 Model")
	return if valid then child else nil
end

local function validateMonsterSlots(errors: { string }, zones: Folder)
	local visitedZones = {}
	local slotsByZone = {}
	local incubatorSlotsByZone = {}
	for _, definition in MonsterSpawnPointCatalog.GetAll() do
		if not visitedZones[definition.ZoneId] then
			visitedZones[definition.ZoneId] = true
			local zone = uniqueContainer(errors, zones, definition.ZoneId)
			if zone then
				slotsByZone[definition.ZoneId] = uniqueContainer(errors, zone, "Slots")
				incubatorSlotsByZone[definition.ZoneId] = uniqueChild(
					errors,
					zone,
					"IncubatorSlots",
					"Folder"
				)
			end
		end
		local slots = slotsByZone[definition.ZoneId]
		local incubatorSlots = incubatorSlotsByZone[definition.ZoneId]
		if slots then
			local point = anchoredPart(errors, slots, definition.SlotId)
			if point then
				add(errors, point:GetAttribute("SlotId") == definition.SlotId, point:GetFullName() .. " SlotId 错误")
				add(errors, point:GetAttribute("ZoneId") == definition.ZoneId, point:GetFullName() .. " ZoneId 错误")
				add(errors, point:GetAttribute("SlotKind") == "MonsterSpawnPoint", point:GetFullName() .. " SlotKind 错误")
			end
		end
		local incubator = MonsterIncubatorConfigs[definition.SpawnPointId]
		add(errors, incubator ~= nil, definition.SpawnPointId .. " 缺少培养罐配置")
		if incubatorSlots and incubator then
			local point = anchoredPart(errors, incubatorSlots, incubator.IncubatorSlotId)
			if point then
				add(errors, point:GetAttribute("SlotId") == incubator.IncubatorSlotId, point:GetFullName() .. " SlotId 错误")
				add(errors, point:GetAttribute("ZoneId") == definition.ZoneId, point:GetFullName() .. " ZoneId 错误")
				add(errors, point:GetAttribute("SlotKind") == "MonsterIncubator", point:GetFullName() .. " SlotKind 错误")
			end
		end
	end
end

-- 防守槽位尚由美术从 Plot01 复制到其他 Plot；存在时严格验证，缺失交给运行时返回稳定错误。
local function validatePresentDefenseMonsterSlots(errors: { string }, zones: Folder)
	for _, definition in DefenseMonsterSlotCatalog.GetAll() do
		local zone = zones:FindFirstChild(definition.RegionId)
		if not zone then
			continue
		end
		local slot, duplicated = UniqueNamedChildAccess.Find(zone, definition.SlotName)
		if duplicated then
			table.insert(errors, zone:GetFullName() .. "/" .. definition.SlotName .. " 存在同名重复项")
			continue
		end
		if slot then
			add(errors, slot:IsA("BasePart"), slot:GetFullName() .. " 必须是 BasePart")
			if slot:IsA("BasePart") then
				add(errors, slot.Anchored, slot:GetFullName() .. " 必须 Anchored")
			end
		end
	end
end

local function validateRebirthButton(errors: { string }, plot: Model)
	local buttons = uniqueChild(errors, plot, "Buttons", "Folder")
	if not buttons then
		return
	end
	local button = uniqueChild(
		errors,
		buttons,
		RebirthProgressionConfigs.Button.ButtonName,
		"Model"
	)
	if not button then
		return
	end
	uniqueChild(errors, button, "Pull", "BasePart")
	add(
		errors,
		AnchoredPartRules.HasOnlyAnchoredParts(button),
		button:GetFullName() .. " 必须只包含 Anchored 的 BasePart"
	)
end

function PlayerPlotContractValidator.ValidatePlot(plot: Model): { string }
	assert(typeof(plot) == "Instance" and plot:IsA("Model"), "plot 必须是 Model")
	local errors = IncomePlotContractValidator.ValidatePlot(plot)
	anchoredPart(errors, plot, "Origin")
	anchoredPart(errors, plot, "AttackViewBounds")
	anchoredPart(errors, plot, "PlayerSpawn")
	validateRebirthButton(errors, plot)
	local zones = uniqueChild(errors, plot, "Zones", "Folder")
	uniqueChild(errors, plot, "Runtime", "Folder")
	if zones then
		validateMonsterSlots(errors, zones :: Folder)
		validatePresentDefenseMonsterSlots(errors, zones :: Folder)
	end
	return errors
end

function PlayerPlotContractValidator.ValidateAll()
	local errors = {}
	local warnings = {}
	local capacityValid, capacityError = validateCapacity()
	if not capacityValid then
		table.insert(warnings, capacityError)
	end
	local root = workspace:FindFirstChild("PlayerPlots")
	add(errors, root ~= nil and root:IsA("Folder"), "Workspace/PlayerPlots 必须是 Folder")
	if not root or not root:IsA("Folder") then
		return {
			Valid = false,
			Errors = errors,
			Warnings = warnings,
			PlotCount = 0,
			RequiredMaxPlayers = EXPECTED_PLOT_COUNT,
			MaxPlayers = Players.MaxPlayers,
			CapacityValid = capacityValid,
		}
	end

	local plots = {}
	for _, child in root:GetChildren() do
		if not child:IsA("Model") then
			table.insert(errors, child:GetFullName() .. " 必须是 Plot Model")
		else
			table.insert(plots, child)
		end
	end
	table.sort(plots, function(a, b)
		return a.Name < b.Name
	end)
	add(
		errors,
		#plots == EXPECTED_PLOT_COUNT,
		string.format("PlayerPlots 必须恰好有 %d 个 Plot，实际为 %d", EXPECTED_PLOT_COUNT, #plots)
	)
	for index, plot in plots do
		add(
			errors,
			plot.Name == string.format("Plot%02d", index),
			string.format("第 %d 个 Plot 名称应为 Plot%02d，实际为 %s", index, index, plot.Name)
		)
		for _, message in PlayerPlotContractValidator.ValidatePlot(plot) do
			table.insert(errors, message)
		end
	end
	return {
		Valid = #errors == 0,
		Errors = errors,
		Warnings = warnings,
		PlotCount = #plots,
		RequiredMaxPlayers = EXPECTED_PLOT_COUNT,
		MaxPlayers = Players.MaxPlayers,
		CapacityValid = capacityValid,
	}
end

function PlayerPlotContractValidator.AssertAll(): boolean
	local result = PlayerPlotContractValidator.ValidateAll()
	if #result.Warnings > 0 then
		warn("玩家 Plot 容量检查警告：\n" .. table.concat(result.Warnings, "\n"))
	end
	assert(result.Valid, "玩家 Plot 场景合同无效：\n" .. table.concat(result.Errors, "\n"))
	return true
end

return PlayerPlotContractValidator
