--[[
	职责：计算一个或多个 Nest 基础结算周期对应的钻石数量。
	输入：Nest 基础钻石、载具钻石倍率、已完成周期数。
	输出：向下取整后的非负钻石数量。
	不负责：计时、玩家余额、载具驻留或奖励发放。
]]

local NestRewardRules = {}

local function validNonNegative(value: number): boolean
	return type(value) == "number" and value == value and value < math.huge and value >= 0
end

function NestRewardRules.CalculatePayout(
	baseDiamonds: number,
	diamondMultiplier: number,
	completedIntervals: number
): number
	assert(validNonNegative(baseDiamonds), "baseDiamonds 必须是有限非负数")
	assert(
		type(diamondMultiplier) == "number"
			and diamondMultiplier == diamondMultiplier
			and diamondMultiplier < math.huge
			and diamondMultiplier > 0,
		"diamondMultiplier 必须是有限正数"
	)
	assert(
		type(completedIntervals) == "number"
			and completedIntervals == completedIntervals
			and completedIntervals < math.huge
			and completedIntervals >= 0
			and completedIntervals % 1 == 0,
		"completedIntervals 必须是有限非负整数"
	)
	return math.floor(baseDiamonds * diamondMultiplier * completedIntervals)
end

return table.freeze(NestRewardRules)
