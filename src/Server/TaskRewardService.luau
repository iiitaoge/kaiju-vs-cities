--[[
	职责：发放任务完成后的金币和钻石奖励。
	输入：player、已通过任务配置校验的奖励数组。
	输出：Succeeded、已发放奖励快照或失败原因。
	内部算法：先验证全部奖励类型和金额，再按顺序复用 MoneyService/DiamondService 写入余额。
	不负责：任务完成判断、奖励配置、领取入口或重复任务周期。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiamondService = require(script.Parent.DiamondService)
local MoneyService = require(script.Parent.MoneyService)
local TaskProtocol = require(ReplicatedStorage.Shared.Task.TaskProtocol)

local TaskRewardService = {}

export type GrantResult = {
	Succeeded: boolean,
	Rewards: { [number]: any }?,
	Reason: string?,
}

local function isValidAmount(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value > 0
end

function TaskRewardService.Grant(player: Player, rewards): GrantResult
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	if type(rewards) ~= "table" or #rewards == 0 then
		return { Succeeded = false, Rewards = nil, Reason = "RewardsMissing" }
	end

	for _, reward in rewards do
		if type(reward) ~= "table"
			or (reward.Kind ~= TaskProtocol.RewardKinds.Money
				and reward.Kind ~= TaskProtocol.RewardKinds.Diamond)
			or not isValidAmount(reward.Amount)
		then
			return { Succeeded = false, Rewards = nil, Reason = "InvalidReward" }
		end
	end

	local succeeded, resultOrError = xpcall(function()
		local granted = {}
		for _, reward in rewards do
			local balance
			if reward.Kind == TaskProtocol.RewardKinds.Money then
				balance = MoneyService.Add(player, reward.Amount)
			else
				balance = DiamondService.Add(player, reward.Amount)
			end
			table.insert(granted, {
				Kind = reward.Kind,
				Amount = reward.Amount,
				Balance = balance,
			})
		end
		return granted
	end, debug.traceback)

	if not succeeded then
		warn(string.format("任务奖励发放失败：%s (%s)", player.Name, tostring(resultOrError)))
		return { Succeeded = false, Rewards = nil, Reason = "RewardGrantFailed" }
	end
	return { Succeeded = true, Rewards = resultOrError, Reason = nil }
end

return table.freeze(TaskRewardService)
