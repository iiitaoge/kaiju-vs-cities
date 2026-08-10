local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroupRewardConfigs = require(
	ReplicatedStorage.Shared.Reward.GroupRewardConfigs
)
local GroupRewardProtocol = require(
	ReplicatedStorage.Shared.Reward.GroupRewardProtocol
)
local GroupRewardRules = require(
	ReplicatedStorage.Shared.Reward.GroupRewardRules
)

local GroupRewardRulesSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "GroupRewardRulesSpec: " .. message)
end

function GroupRewardRulesSpec.Run(): boolean
	local valid, reason = GroupRewardRules.ValidateConfig(GroupRewardConfigs)
	expect(valid and reason == nil, "默认群组奖励配置必须有效")
	expect(GroupRewardConfigs.GroupId == 551880636, "群组 ID 配置错误")
	expect(#GroupRewardConfigs.Rewards == 2, "默认必须同时配置两项奖励")
	expect(
		GroupRewardConfigs.Rewards[1].Type == GroupRewardProtocol.Types.Money
			and GroupRewardConfigs.Rewards[1].Amount == 500000,
		"默认现金奖励配置错误"
	)
	expect(
		GroupRewardConfigs.Rewards[2].Type == GroupRewardProtocol.Types.Diamond
			and GroupRewardConfigs.Rewards[2].Amount == 500,
		"默认钻石奖励配置错误"
	)

	local claimable = GroupRewardRules.GetState(true, false, GroupRewardConfigs)
	expect(
		claimable.Status == GroupRewardProtocol.Statuses.Claimable
			and claimable.Available,
		"群组成员未领取时必须可领取"
	)

	local notMember = GroupRewardRules.GetState(false, false, GroupRewardConfigs)
	expect(
		notMember.Status == GroupRewardProtocol.Statuses.NotMember
			and not notMember.Available,
		"非群组成员不得领取"
	)

	local claimed = GroupRewardRules.GetState(true, true, GroupRewardConfigs)
	expect(
		claimed.Status == GroupRewardProtocol.Statuses.Claimed
			and not claimed.Available,
		"已领取奖励必须进入完成态"
	)

	local canClaim, claimReason = GroupRewardRules.CanClaim(true, false)
	expect(canClaim and claimReason == nil, "成员未领取时必须允许领取")
	local claimedAllowed, claimedReason = GroupRewardRules.CanClaim(true, true)
	expect(
		not claimedAllowed
			and claimedReason == GroupRewardProtocol.Reasons.RewardAlreadyClaimed,
		"已领取奖励不得重复领取"
	)
	local memberAllowed, memberReason = GroupRewardRules.CanClaim(false, false)
	expect(
		not memberAllowed
			and memberReason == GroupRewardProtocol.Reasons.NotGroupMember,
		"非群组成员必须被拒绝"
	)

	local unsupported, unsupportedReason = GroupRewardRules.ValidateConfig({
		GroupId = 551880636,
		RewardId = "Unsupported",
		Rewards = { { Type = "Godzilla", MonsterKey = "Godzilla" } },
	})
	expect(
		not unsupported
			and unsupportedReason == GroupRewardProtocol.Reasons.UnsupportedRewardType,
		"未实现奖励类型必须被拒绝"
	)

	local invalidAmount, invalidAmountReason = GroupRewardRules.ValidateConfig({
		GroupId = 551880636,
		RewardId = "InvalidAmount",
		Rewards = { { Type = GroupRewardProtocol.Types.Money, Amount = -1 } },
	})
	expect(
		not invalidAmount
			and invalidAmountReason == GroupRewardProtocol.Reasons.InvalidRewardConfig,
		"非法奖励数值必须被拒绝"
	)

	return true
end

return GroupRewardRulesSpec
