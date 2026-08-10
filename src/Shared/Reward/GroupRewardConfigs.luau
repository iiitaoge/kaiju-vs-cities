--[[
	职责：提供当前群组奖励的可编辑配置。
	输入：无；策划只需要修改 GroupId、RewardId 或 Rewards 中的奖励项。
	输出：一个群组奖励活动配置；同一 RewardId 每名玩家只能领取一次。
	内部算法：初始化并冻结纯配置表。
	不负责：群组校验、奖励规则、余额修改、存档、Remote 或 UI。

	RewardId 是领取幂等键。若未来要做一批新的群组活动，应改成新的 RewardId，
	而不是覆盖旧 RewardId，否则已领取玩家不会再次获得新配置。
]]

local GroupRewardProtocol = require(script.Parent.GroupRewardProtocol)

local types = GroupRewardProtocol.Types
local rewards = {
	{ Type = types.Money, Amount = 500000 },
	{ Type = types.Diamond, Amount = 500 },
}

for _, reward in rewards do
	table.freeze(reward)
end

return table.freeze({
	GroupId = 551880636,
	RewardId = "GroupJoinRewardV1",
	Rewards = table.freeze(rewards),
})
