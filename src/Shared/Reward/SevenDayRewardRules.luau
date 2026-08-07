--[[
	职责：计算七日奖励的可领取状态和领取后的下一状态。
	输入：当前状态 { Day, NextClaimAt }、当前 Unix 时间和奖励配置。
	输出：状态快照，或不修改原状态的领取结果与下一状态。
	内部算法：顺序锁定 Day；只有当前 Day 且 now >= NextClaimAt 时允许领取；领取后把下一档
	的 NextClaimAt 设置为 now + 24 小时；第七档后进入完成态，不跳过未领取的档位。
	不负责：玩家、Instance、货币余额、存档、Remote 或 UI。
]]

local CurrencyProtocol = require(script.Parent.Parent.Economy.CurrencyProtocol)
local SevenDayRewardProtocol = require(script.Parent.SevenDayRewardProtocol)

local SevenDayRewardRules = {}

local function isFiniteNonNegativeInteger(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
		and value % 1 == 0
end

local function isPositiveInteger(value): boolean
	return isFiniteNonNegativeInteger(value) and value > 0
end

local function validateNow(now: number)
	assert(isFiniteNonNegativeInteger(now), "now 必须是非负整数")
end

local function validateState(state)
	assert(type(state) == "table", "state 必须是 table")
	assert(
		isFiniteNonNegativeInteger(state.Day) and state.Day >= 1,
		"state.Day 必须是正整数"
	)
	assert(
		isFiniteNonNegativeInteger(state.NextClaimAt),
		"state.NextClaimAt 必须是非负整数"
	)
end

function SevenDayRewardRules.ValidateConfig(config): (boolean, string?)
	if type(config) ~= "table"
		or not isPositiveInteger(config.TotalDays)
		or not isPositiveInteger(config.CooldownSeconds)
		or type(config.Days) ~= "table"
	then
		return false, SevenDayRewardProtocol.Reasons.InvalidRewardConfig
	end

	for day = 1, config.TotalDays do
		local reward = config.Days[day]
		if type(reward) ~= "table"
			or reward.Day ~= day
			or (reward.Type ~= CurrencyProtocol.Types.Money
				and reward.Type ~= CurrencyProtocol.Types.Diamond)
			or not isFiniteNonNegativeInteger(reward.Amount)
		then
			return false, SevenDayRewardProtocol.Reasons.InvalidRewardConfig
		end
	end

	return true, nil
end

local function assertValidConfig(config)
	local valid, reason = SevenDayRewardRules.ValidateConfig(config)
	assert(valid, reason or SevenDayRewardProtocol.Reasons.InvalidRewardConfig)
end

function SevenDayRewardRules.GetInitialState()
	return {
		Day = 1,
		NextClaimAt = 0,
	}
end

function SevenDayRewardRules.GetState(state, now: number, config)
	validateState(state)
	validateNow(now)
	assertValidConfig(config)

	local completedDay = config.TotalDays + 1
	if state.Day >= completedDay then
		return {
			Status = SevenDayRewardProtocol.Statuses.Completed,
			Day = completedDay,
			Available = false,
			NextClaimAt = 0,
			RemainingSeconds = 0,
			Reward = nil,
		}
	end

	local remainingSeconds = math.max(0, state.NextClaimAt - now)
	local available = remainingSeconds == 0
	return {
		Status = if available
			then SevenDayRewardProtocol.Statuses.Claimable
			else SevenDayRewardProtocol.Statuses.Cooldown,
		Day = state.Day,
		Available = available,
		NextClaimAt = state.NextClaimAt,
		RemainingSeconds = remainingSeconds,
		Reward = config.Days[state.Day],
	}
end

function SevenDayRewardRules.Claim(state, now: number, config)
	local snapshot = SevenDayRewardRules.GetState(state, now, config)
	if snapshot.Status == SevenDayRewardProtocol.Statuses.Completed then
		return nil, SevenDayRewardProtocol.Reasons.RewardCompleted
	end
	if snapshot.Status == SevenDayRewardProtocol.Statuses.Cooldown then
		return nil, SevenDayRewardProtocol.Reasons.RewardCooldown
	end

	local claimedDay = snapshot.Day
	local nextDay = claimedDay + 1
	local nextClaimAt = if nextDay > config.TotalDays
		then 0
		else now + config.CooldownSeconds
	return {
		ClaimedDay = claimedDay,
		Reward = snapshot.Reward,
		State = {
			Day = nextDay,
			NextClaimAt = nextClaimAt,
		},
	}, nil
end

return table.freeze(SevenDayRewardRules)
