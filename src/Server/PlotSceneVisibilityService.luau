--[[
	职责：按外部提供的 Zone 状态，控制单个 Plot 的静态 Zone 场景可见性。

	输入：ApplyZone/ApplyAll 接收 Plot 和 Zone 状态解析器；ApplyDefault 使用
	ZoneCatalog.InitialUnlocked 与默认等级 0。
	输出：应用结果，以及 Decoration/按钮处理数量。
	内部算法：根据 Zone 解锁状态显示 Decoration 和业务按钮；锁定 Zone 只显示
	满足前置条件的 Unlock 按钮；属性恢复委托 ZoneSceneVisibility。

	不负责：读取玩家状态、分配 Plot、修改解锁状态、创建或复制场景。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZoneSceneVisibility = require(script.Parent.ZoneSceneVisibility)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local PlotSceneVisibilityService = {}

export type ZoneState = {
	Unlocked: boolean,
	Level: number,
}

export type StateResolver = (zoneId: string) -> ZoneState

export type ApplyResult = {
	Succeeded: boolean,
	Reason: string?,
	DecorationCount: number,
	ButtonCount: number,
}

export type ApplyAllResult = {
	Succeeded: boolean,
	Reason: string?,
	AppliedCount: number,
}

local function isContainer(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("Model") or instance:IsA("Folder"))
end

local function result(
	succeeded: boolean,
	reason: string?,
	decorationCount: number,
	buttonCount: number
): ApplyResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		DecorationCount = decorationCount,
		ButtonCount = buttonCount,
	}
end

local function resolveState(stateResolver: StateResolver, zoneId: string): ZoneState
	local state = stateResolver(zoneId)
	assert(type(state) == "table", "Zone 状态解析器必须返回 table")
	assert(type(state.Unlocked) == "boolean", "Zone.Unlocked 必须是 boolean")
	assert(
		type(state.Level) == "number" and state.Level == state.Level,
		"Zone.Level 必须是有限数字"
	)
	return state
end

local function setRegionPanelVisible(zone: Instance, visible: boolean)
	local region = zone:FindFirstChild("Region")
	local attachment = region and region:FindFirstChild("Attachment")
	local billboardGui = attachment and attachment:FindFirstChild("BillboardGui")
	local panel = billboardGui and billboardGui:FindFirstChild("Panel")
	if panel and panel:IsA("GuiObject") then
		panel.Visible = visible
	end
end

function PlotSceneVisibilityService.ApplyZone(
	plot: Model,
	zoneId: string,
	stateResolver: StateResolver
): ApplyResult
	assert(typeof(plot) == "Instance" and plot:IsA("Model"), "plot 必须是 Model")
	assert(type(zoneId) == "string" and zoneId ~= "", "zoneId 必须是非空字符串")
	assert(type(stateResolver) == "function", "stateResolver 必须是函数")

	local definition = ZoneCatalog.Get(zoneId)
	if not definition then
		return result(false, "UnknownZone", 0, 0)
	end

	local zones = plot:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(zoneId)
	if not isContainer(zone) then
		return result(false, "ZoneSceneUnavailable", 0, 0)
	end

	local state = resolveState(stateResolver, zoneId)
	local prerequisiteMet = true
	local prerequisiteZoneId = definition.UnlockPrerequisiteZoneId
	if prerequisiteZoneId then
		local prerequisiteState = resolveState(stateResolver, prerequisiteZoneId)
		prerequisiteMet = prerequisiteState.Unlocked
			and prerequisiteState.Level >= assert(definition.UnlockPrerequisiteLevel)
	end

	local decorationCount = 0
	local decoration = zone:FindFirstChild("Decoration")
	if isContainer(decoration) then
		ZoneSceneVisibility.SetVisible(decoration, state.Unlocked)
		decorationCount = 1
	end
	setRegionPanelVisible(zone, state.Unlocked)

	local buttonCount = 0
	local buttons = zone:FindFirstChild("Buttons")
	if buttons and buttons:IsA("Folder") then
		local unlockButtonName = zoneId .. "-Unlock-Button"
		for _, child in buttons:GetChildren() do
			if not child:IsA("Model") then
				continue
			end
			local isUnlockButton = child.Name == unlockButtonName
			local visible = if state.Unlocked
				then not isUnlockButton
				else isUnlockButton and prerequisiteMet
			ZoneSceneVisibility.SetVisible(child, visible)
			buttonCount += 1
		end
	end

	return result(true, nil, decorationCount, buttonCount)
end

function PlotSceneVisibilityService.ApplyAll(
	plot: Model,
	stateResolver: StateResolver
): ApplyAllResult
	local appliedCount = 0
	for _, definition in ZoneCatalog.GetAll() do
		local applied = PlotSceneVisibilityService.ApplyZone(
			plot,
			definition.ZoneId,
			stateResolver
		)
		if applied.Succeeded then
			appliedCount += 1
		elseif applied.Reason ~= "ZoneSceneUnavailable" then
			return {
				Succeeded = false,
				Reason = applied.Reason,
				AppliedCount = appliedCount,
			}
		end
	end
	return {
		Succeeded = true,
		Reason = nil,
		AppliedCount = appliedCount,
	}
end

function PlotSceneVisibilityService.ApplyDefault(plot: Model): ApplyAllResult
	return PlotSceneVisibilityService.ApplyAll(plot, function(zoneId)
		local definition = assert(ZoneCatalog.Get(zoneId))
		return {
			Unlocked = definition.InitialUnlocked,
			Level = 0,
		}
	end)
end

return PlotSceneVisibilityService
