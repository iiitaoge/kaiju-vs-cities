--[[
	职责：校验群组奖励配置，并根据成员/领取状态计算可领取状态。
	输入：奖励配置、玩家是否为群组成员、玩家是否领取过当前 RewardId。
	输出：配置校验结果、可领取状态和稳定失败原因。
	内部算法：按 Type 选择对应字段校验；当前 Money/Diamond 要求有限非负整数 Amount；
	领取状态优先于成员状态，已领取玩家即使之后退群也保持 Claimed。
	不负责：调用 Roblox 群组 API、修改货币、修改存档、Remote 或 UI。
]]

local GroupRewardProtocol = require(script.Parent.GroupRewardProtocol)

local GroupRewardRules = {}
local types = GroupRewardProtocol.Types
local reasons = GroupRewardProtocol.Reasons

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

local function isValidRewardId(value): boolean
	return type(value) == "string"
		and value ~= ""
		and string.match(value, "^[A-Za-z0-9_.%-]+$") ~= nil
end

local function validateReward(reward): (boolean, string?)
	if type(reward) ~= "table" then
		return false, reasons.InvalidRewardConfig
	end

	if reward.Type == types.Money or reward.Type == types.Diamond then
		if not isFiniteNonNegativeInteger(reward.Amount) then
			return false, reasons.InvalidRewardConfig
		end
		return true, nil
	end

	return false, reasons.UnsupportedRewardType
end

function GroupRewardRules.ValidateConfig(config): (boolean, string?)
	if type(config) ~= "table"
		or not isPositiveInteger(config.GroupId)
		or not isValidRewardId(config.RewardId)
		or type(config.Rewards) ~= "table"
		or #config.Rewards == 0
	then
		return false, reasons.InvalidRewardConfig
	end

	for index = 1, #config.Rewards do
		local valid, reason = validateReward(config.Rewards[index])
		if not valid then
			return false, reason
		end
	end

	return true, nil
end

function GroupRewardRules.GetState(
	isMember: boolean,
	claimed: boolean,
	config
)
	assert(type(isMember) == "boolean", "isMember 必须是 boolean")
	assert(type(claimed) == "boolean", "claimed 必须是 boolean")

	local status = if claimed
		then GroupRewardProtocol.Statuses.Claimed
		elseif isMember
		then GroupRewardProtocol.Statuses.Claimable
		else GroupRewardProtocol.Statuses.NotMember

	return {
		Status = status,
		Available = status == GroupRewardProtocol.Statuses.Claimable,
		IsMember = isMember,
		Claimed = claimed,
		GroupId = config.GroupId,
		RewardId = config.RewardId,
		Rewards = config.Rewards,
	}
end

function GroupRewardRules.CanClaim(isMember: boolean, claimed: boolean): (boolean, string?)
	assert(type(isMember) == "boolean", "isMember 必须是 boolean")
	assert(type(claimed) == "boolean", "claimed 必须是 boolean")

	if claimed then
		return false, reasons.RewardAlreadyClaimed
	end
	if not isMember then
		return false, reasons.NotGroupMember
	end
	return true, nil
end

return table.freeze(GroupRewardRules)
