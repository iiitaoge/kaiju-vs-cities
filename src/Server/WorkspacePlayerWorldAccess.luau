--[[
	职责：组装正式 Workspace Plot、Zone 状态与三个场景适配器。
	输出：Territory、AttackView、Slots；业务链路只依赖这些稳定接口。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local WorkspacePlayerAttackViewAccess = require(script.Parent.WorkspacePlayerAttackViewAccess)
local WorkspacePlayerTerritoryAccess = require(script.Parent.WorkspacePlayerTerritoryAccess)
local WorkspaceZoneSlotAccess = require(script.Parent.WorkspaceZoneSlotAccess)
local ZoneStateService = require(script.Parent.ZoneStateService)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local function getPlot(player: Player): Model?
	return PlayerPlotAssignmentService.GetPlot(player)
end

local function getZoneDefinitions()
	return ZoneCatalog.GetAll()
end

local function isZoneUnlocked(player: Player, zoneId: string): boolean
	return ZoneStateService.GetUnlocked(player, zoneId)
end

return table.freeze({
	Territory = WorkspacePlayerTerritoryAccess.Create({
		GetPlot = getPlot,
		GetZoneDefinitions = getZoneDefinitions,
		IsZoneUnlocked = isZoneUnlocked,
	}),
	AttackView = WorkspacePlayerAttackViewAccess.Create({
		GetPlot = getPlot,
	}),
	Slots = WorkspaceZoneSlotAccess.Create({
		GetPlot = getPlot,
		GetZoneDefinitions = getZoneDefinitions,
		IsZoneUnlocked = isZoneUnlocked,
	}),
})
