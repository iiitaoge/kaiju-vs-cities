local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterLevelLimitRules = require(
	ReplicatedStorage.Shared.Monster.MonsterLevelLimitRules
)

local Spec = {}

function Spec.Run(): boolean
	assert(
		MonsterLevelLimitRules.ResolveMaxLevel(0, 15, 5) == 15,
		"零次重生应只解锁第一形态"
	)
	assert(
		MonsterLevelLimitRules.ResolveMaxLevel(1, 15, 5) == 30,
		"一次重生应解锁第二形态"
	)
	assert(
		MonsterLevelLimitRules.ResolveMaxLevel(4, 15, 5) == 75,
		"解锁全部形态后应封顶总等级"
	)
	assert(
		MonsterLevelLimitRules.ResolveMaxLevel(99, 15, 5) == 75,
		"超过形态数后仍应封顶总等级"
	)

	local allowed, allowedReason = MonsterLevelLimitRules.CheckTargetLevel(15, 15, 75)
	assert(allowed and allowedReason == nil, "当前上限内应允许升级")
	local requiresRebirth, rebirthReason = MonsterLevelLimitRules.CheckTargetLevel(16, 15, 75)
	assert(not requiresRebirth and rebirthReason == "RebirthRequired", "跨形态升级应要求重生")
	local maxed, maxedReason = MonsterLevelLimitRules.CheckTargetLevel(76, 75, 75)
	assert(not maxed and maxedReason == "MaxLevel", "超过成长线总等级应判定为满级")

	assert(not pcall(MonsterLevelLimitRules.ResolveMaxLevel, -1, 15, 5), "负重生次数未被拒绝")
	assert(not pcall(MonsterLevelLimitRules.ResolveMaxLevel, 0, 0, 5), "非法每形态等级未被拒绝")
	return true
end

return Spec
