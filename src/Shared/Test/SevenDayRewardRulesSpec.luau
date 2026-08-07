local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SevenDayRewardConfigs = require(
	ReplicatedStorage.Shared.Reward.SevenDayRewardConfigs
)
local SevenDayRewardProtocol = require(
	ReplicatedStorage.Shared.Reward.SevenDayRewardProtocol
)
local SevenDayRewardRules = require(
	ReplicatedStorage.Shared.Reward.SevenDayRewardRules
)

local SevenDayRewardRulesSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "SevenDayRewardRulesSpec: " .. message)
end

function SevenDayRewardRulesSpec.Run(): boolean
	local valid, configReason = SevenDayRewardRules.ValidateConfig(SevenDayRewardConfigs)
	expect(valid and configReason == nil, "默认奖励配置必须有效")

	local initial = SevenDayRewardRules.GetInitialState()
	local firstState = SevenDayRewardRules.GetState(initial, 100, SevenDayRewardConfigs)
	expect(
		firstState.Status == SevenDayRewardProtocol.Statuses.Claimable
			and firstState.Day == 1
			and firstState.Reward.Type == SevenDayRewardConfigs.CurrencyTypes.Money,
		"第一天必须立即可领取"
	)

	local firstClaim = SevenDayRewardRules.Claim(initial, 100, SevenDayRewardConfigs)
	expect(firstClaim ~= nil and firstClaim.ClaimedDay == 1, "第一天领取结果错误")
	expect(
		firstClaim.State.Day == 2
			and firstClaim.State.NextClaimAt == 100 + SevenDayRewardConfigs.CooldownSeconds,
		"第一天领取后必须锁定第二天 24 小时"
	)

	local beforeCooldown = SevenDayRewardRules.Claim(
		firstClaim.State,
		firstClaim.State.NextClaimAt - 1,
		SevenDayRewardConfigs
	)
	expect(
		beforeCooldown == nil,
		"24 小时未到时不得领取下一天"
	)
	local secondClaim = SevenDayRewardRules.Claim(
		firstClaim.State,
		firstClaim.State.NextClaimAt,
		SevenDayRewardConfigs
	)
	expect(secondClaim ~= nil and secondClaim.ClaimedDay == 2, "第二天领取结果错误")

	local lateTime = secondClaim.State.NextClaimAt + 100000
	local lateState = SevenDayRewardRules.GetState(
		secondClaim.State,
		lateTime,
		SevenDayRewardConfigs
	)
	expect(
		lateState.Day == 3 and lateState.Reward.Day == 3,
		"漏过冷却时间时不得跳过当前未领取档位"
	)
	local state = secondClaim.State
	local time = lateTime
	local lastClaim
	for expectedDay = 3, 7 do
		if expectedDay ~= 3 then
			time = state.NextClaimAt
		end
		lastClaim = SevenDayRewardRules.Claim(state, time, SevenDayRewardConfigs)
		expect(lastClaim ~= nil and lastClaim.ClaimedDay == expectedDay, "顺序领取档位错误")
		state = lastClaim.State
	end

	local completed = SevenDayRewardRules.GetState(state, time, SevenDayRewardConfigs)
	expect(
		completed.Status == SevenDayRewardProtocol.Statuses.Completed
			and completed.Day == 8
			and completed.Reward == nil,
		"第七天领取后必须进入完成态"
	)
	local afterCompleted = SevenDayRewardRules.Claim(state, time, SevenDayRewardConfigs)
	expect(afterCompleted == nil, "完成七日后不得重复领取")
	return true
end

return SevenDayRewardRulesSpec
