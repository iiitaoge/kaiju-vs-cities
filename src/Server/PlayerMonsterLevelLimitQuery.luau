--[[
	职责：把在线玩家的重生次数转换成某条怪兽成长线的等级上限。
	输入：Player 和 ProgressionId，或显式的重生次数与 ProgressionId。
	输出：当前阶段上限、成长线总上限和使用的重生次数。
	内部算法：读取成长线的每形态等级数/形态数，委托共享纯规则计算上限。
	不负责：怪兽升级、资格判断、存档写入、模型生成或 UI 表现。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthStateService = require(script.Parent.RebirthStateService)
local MonsterLevelLimitRules = require(
	ReplicatedStorage.Shared.Monster.MonsterLevelLimitRules
)
local MonsterLevelProgressionRules = require(
	ReplicatedStorage.Shared.Monster.MonsterLevelProgressionRules
)
local MonsterProgressionConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterProgressionConfigs
)

local PlayerMonsterLevelLimitQuery = {}

export type Snapshot = {
	RebirthCount: number,
	MaxLevel: number,
	TotalMaxLevel: number,
}

local function resolve(rebirthCount: number, progressionId: string): Snapshot?
	local progression = MonsterProgressionConfigs[progressionId]
	if not progression then
		return nil
	end

	local totalMaxLevel = MonsterLevelProgressionRules.GetMaxLevel(
		progression.LevelsPerForm,
		progression.FormCount
	)
	return table.freeze({
		RebirthCount = rebirthCount,
		MaxLevel = MonsterLevelLimitRules.ResolveMaxLevel(
			rebirthCount,
			progression.LevelsPerForm,
			progression.FormCount
		),
		TotalMaxLevel = totalMaxLevel,
	})
end

function PlayerMonsterLevelLimitQuery.Get(
	player: Player,
	progressionId: string
): Snapshot?
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(progressionId) == "string" and progressionId ~= "", "progressionId 无效")
	return resolve(RebirthStateService.Get(player).Count, progressionId)
end

function PlayerMonsterLevelLimitQuery.GetForRebirthCount(
	rebirthCount: number,
	progressionId: string
): Snapshot?
	assert(type(progressionId) == "string" and progressionId ~= "", "progressionId 无效")
	return resolve(rebirthCount, progressionId)
end

return table.freeze(PlayerMonsterLevelLimitQuery)
