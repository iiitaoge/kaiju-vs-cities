--[[
	职责：组装正式在线玩家、怪兽名册和 Workspace Zone Bounds 的区域占用查询。
	输出：PlayerRegionMonsterOccupancyQuery.Access。
]]

local Players = game:GetService("Players")

local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local PlayerRegionMonsterOccupancyQuery = require(
	script.Parent.PlayerRegionMonsterOccupancyQuery
)
local WorkspacePlayerWorldAccess = require(script.Parent.WorkspacePlayerWorldAccess)

return PlayerRegionMonsterOccupancyQuery.Create({
	GetPlayers = function(): { Player }
		return Players:GetPlayers()
	end,
	ListTerritories = WorkspacePlayerWorldAccess.Territory.ListUnlockedTerritories,
	ListMonsters = MonsterRosterCoordinator.List,
})
