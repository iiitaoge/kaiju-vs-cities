--[[
	职责：管理房屋被摧毁期间的服务器权威废墟 Model。

	场景合同：
	- ReplicatedStorage/Buildings/Ruins/Ruin1 (Model)
	- PlayerPlot/Runtime/Ruins (Folder；按需创建)

	输入：Ensure/Remove 接收在线 Player 和 HouseId；ClearPlot 接收 Plot。
	输出：Ensure 返回已存在或新建的废墟；Remove/Ensure 返回稳定失败原因；
		废墟作为服务器 Model 复制给当前及晚加入的客户端。
	内部算法：按 HouseId 找到对应 IncomeBuilding Slot，使用 Ruin1 的模板 Pivot
		适配 Slot CFrame；废墟使用 HouseId 作为唯一名称，并写入 Ruin 身份 Attributes。

	不负责：房屋状态转换、重建调度、房屋建筑生成、客户端动画或收入。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingPlacement = require(ReplicatedStorage.Shared.Building.BuildingPlacement)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local WorkspacePlayerWorldAccess = require(script.Parent.WorkspacePlayerWorldAccess)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)

local HouseRuinRuntimeService = {}

local RUIN_TEMPLATE_PATH = "ReplicatedStorage/Buildings/Ruins/Ruin1"
local RUINS_ROOT_NAME = "Ruins"
local INCOME_SLOT_KIND = "IncomeBuilding"

local OWNER_ATTRIBUTE = "RuinOwnerUserId"
local HOUSE_ATTRIBUTE = "RuinHouseId"
local ZONE_ATTRIBUTE = "RuinZoneId"
local SLOT_ATTRIBUTE = "RuinSlotId"

local function getTemplate(): (Model?, string?)
	local template = InstancePath.Find(RUIN_TEMPLATE_PATH)
	if not template then
		return nil, "RuinTemplateUnavailable"
	end
	if not template:IsA("Model") then
		return nil, "RuinTemplateInvalid"
	end
	return template, nil
end

local function getRuinsRoot(plot: Model): Folder?
	local runtime = plot:FindFirstChild("Runtime")
	local ruins = runtime and runtime:FindFirstChild(RUINS_ROOT_NAME)
	return if ruins and ruins:IsA("Folder") then ruins else nil
end

local function getOrCreateRuinsRoot(plot: Model): (Folder?, string?)
	local runtime = plot:FindFirstChild("Runtime")
	if not runtime or not runtime:IsA("Folder") then
		return nil, "MissingPlotRuntime"
	end

	local existing = runtime:FindFirstChild(RUINS_ROOT_NAME)
	if existing then
		if not existing:IsA("Folder") then
			return nil, "InvalidRuinsRuntime"
		end
		return existing, nil
	end

	local ruins = Instance.new("Folder")
	ruins.Name = RUINS_ROOT_NAME
	ruins.Parent = runtime
	return ruins, nil
end

local function resolveSlot(player: Player, houseId: string): (any?, string?)
	local definition = HouseCatalog.Get(houseId)
	if not definition then
		return nil, "UnknownHouse"
	end

	for _, slot in WorkspacePlayerWorldAccess.Slots.ListUnlockedSlots(
		player,
		INCOME_SLOT_KIND
	) do
		if slot.SlotId == houseId then
			return slot, nil
		end
	end
	return nil, "MissingBuildingSlot"
end

local function hasIdentity(model: Model, player: Player, houseId: string): boolean
	local definition = HouseCatalog.Get(houseId)
	return definition ~= nil
		and model:GetAttribute(OWNER_ATTRIBUTE) == player.UserId
		and model:GetAttribute(HOUSE_ATTRIBUTE) == houseId
		and model:GetAttribute(ZONE_ATTRIBUTE) == definition.RegionId
		and model:GetAttribute(SLOT_ATTRIBUTE) == houseId
end

local function prepareRuin(
	template: Model,
	player: Player,
	houseId: string,
	targetPivot: CFrame,
	parent: Folder
): (Model?, string?)
	local definition = assert(HouseCatalog.Get(houseId))
	local ruin = template:Clone()
	ruin.Name = houseId
	ruin:SetAttribute(OWNER_ATTRIBUTE, player.UserId)
	ruin:SetAttribute(HOUSE_ATTRIBUTE, houseId)
	ruin:SetAttribute(ZONE_ATTRIBUTE, definition.RegionId)
	ruin:SetAttribute(SLOT_ATTRIBUTE, houseId)

	local basePartCount = 0
	for _, descendant in ruin:GetDescendants() do
		if descendant:IsA("BasePart") then
			basePartCount += 1
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	if basePartCount == 0 then
		ruin:Destroy()
		return nil, "RuinTemplateEmpty"
	end

	ruin:PivotTo(targetPivot)
	ruin.Parent = parent
	return ruin, nil
end

function HouseRuinRuntimeService.Ensure(
	player: Player,
	houseId: string
): (Model?, string?)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	if player.Parent ~= Players then
		return nil, "PlayerUnavailable"
	end

	local definition = HouseCatalog.Get(houseId)
	if not definition then
		return nil, "UnknownHouse"
	end
	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return nil, plotReason or "PlayerHasNoPlot"
	end
	local slot, slotReason = resolveSlot(player, houseId)
	if not slot then
		return nil, slotReason or "MissingBuildingSlot"
	end
	local template, templateReason = getTemplate()
	if not template then
		return nil, templateReason or "RuinTemplateUnavailable"
	end
	local ruins, runtimeReason = getOrCreateRuinsRoot(plot)
	if not ruins then
		return nil, runtimeReason or "MissingRuinsRuntime"
	end

	local existing = ruins:FindFirstChild(houseId)
	if existing then
		if not existing:IsA("Model") then
			return nil, "InvalidRuinModel"
		end
		if not hasIdentity(existing, player, houseId) then
			return nil, "RuinIdentityMismatch"
		end
		return existing, nil
	end

	local targetPivot = BuildingPlacement.GetTargetPivot(template, slot.Point.CFrame)
	return prepareRuin(template, player, houseId, targetPivot, ruins)
end

function HouseRuinRuntimeService.Remove(
	player: Player,
	houseId: string
): (boolean, string?)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	if player.Parent ~= Players then
		return false, "PlayerUnavailable"
	end

	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return false, plotReason or "PlayerHasNoPlot"
	end
	local ruins = getRuinsRoot(plot)
	if not ruins then
		return true, nil
	end

	local existing = ruins:FindFirstChild(houseId)
	if not existing then
		return true, nil
	end
	if not existing:IsA("Model") then
		return false, "InvalidRuinModel"
	end
	if not hasIdentity(existing, player, houseId) then
		return false, "RuinIdentityMismatch"
	end

	existing:Destroy()
	if #ruins:GetChildren() == 0 then
		ruins:Destroy()
	end
	return true, nil
end

function HouseRuinRuntimeService.ClearPlot(plot: Model): number
	assert(typeof(plot) == "Instance" and plot:IsA("Model"), "plot 必须是 Model")
	local ruins = getRuinsRoot(plot)
	if not ruins then
		return 0
	end
	local count = #ruins:GetChildren()
	ruins:Destroy()
	return count
end

return HouseRuinRuntimeService
