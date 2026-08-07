--[[
	职责：维护七日奖励的服务器运行时状态。
	输入：Get/Set/Restore 接收 player 和 Day、NextClaimAt。
	输出：{ Day, NextClaimAt } 快照。
	内部算法：把状态写入 RuntimePlayerStates/<UserId>/Rewards Attributes；首次读取时创建第一天状态。
	不负责：判断冷却、解析奖励内容、发放货币、DataStore、Remote 或 UI。
]]

local PlayerStateService = require(script.Parent.PlayerStateService)

local SevenDayRewardStateService = {}

export type Snapshot = {
	Day: number,
	NextClaimAt: number,
}

local DEFAULT_DAY = 1
local DEFAULT_NEXT_CLAIM_AT = 0

local function assertNonNegativeInteger(value: number, name: string)
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value >= 0
			and value % 1 == 0,
		name .. " 必须是非负整数"
	)
end

local function getSection(player: Player): Folder
	local section = PlayerStateService.GetSection(player, "Rewards")
	if section:GetAttribute("DailyRewardDay") == nil then
		section:SetAttribute("DailyRewardDay", DEFAULT_DAY)
	end
	if section:GetAttribute("DailyRewardNextClaimAt") == nil then
		section:SetAttribute("DailyRewardNextClaimAt", DEFAULT_NEXT_CLAIM_AT)
	end
	return section
end

function SevenDayRewardStateService.Get(player: Player): Snapshot
	local section = getSection(player)
	return {
		Day = section:GetAttribute("DailyRewardDay") or DEFAULT_DAY,
		NextClaimAt = section:GetAttribute("DailyRewardNextClaimAt")
			or DEFAULT_NEXT_CLAIM_AT,
	}
end

function SevenDayRewardStateService.Set(
	player: Player,
	day: number,
	nextClaimAt: number
): Snapshot
	assertNonNegativeInteger(day, "day")
	assert(day >= 1, "day 必须是正整数")
	assertNonNegativeInteger(nextClaimAt, "nextClaimAt")

	local section = getSection(player)
	section:SetAttribute("DailyRewardDay", day)
	section:SetAttribute("DailyRewardNextClaimAt", nextClaimAt)
	return SevenDayRewardStateService.Get(player)
end

function SevenDayRewardStateService.Restore(
	player: Player,
	day: number,
	nextClaimAt: number
): Snapshot
	return SevenDayRewardStateService.Set(player, day, nextClaimAt)
end

return SevenDayRewardStateService
