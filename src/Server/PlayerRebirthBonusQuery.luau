--[[
	职责：解析在线玩家当前重生次数对应的五项权威倍率。
	输入：Player。
	输出：只读的 Income/BuildSpeed/MonsterDamage/MonsterHealth/MonsterMoveSpeed 倍率快照。
	内部算法：读取 RebirthStateService 次数，组合纯规则与集中配置。
	不负责：修改重生状态、应用倍率、存档、表现或业务事务。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthStateService = require(script.Parent.RebirthStateService)
local RebirthProgressionConfigs = require(
	ReplicatedStorage.Shared.Progression.RebirthProgressionConfigs
)
local RebirthProgressionRules = require(
	ReplicatedStorage.Shared.Progression.RebirthProgressionRules
)

local PlayerRebirthBonusQuery = {}

function PlayerRebirthBonusQuery.Get(player: Player): RebirthProgressionRules.BonusSnapshot
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local state = RebirthStateService.Get(player)
	return table.freeze(RebirthProgressionRules.ResolveBonuses(
		state.Count,
		RebirthProgressionConfigs.Bonuses
	))
end

return table.freeze(PlayerRebirthBonusQuery)
