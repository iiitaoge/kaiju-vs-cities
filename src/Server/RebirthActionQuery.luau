--[[
	职责：生成玩家当前的服务器权威重生资格和倍率快照。
	输入：Player。
	输出：次数、本轮累计收入、门槛、剩余收入、是否允许，以及当前/下一次五项倍率。
	内部算法：读取 RebirthStateService，再委托共享纯规则和配置。
	不负责：按钮、Remote、状态机、存档提交或运行时重载。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthStateService = require(script.Parent.RebirthStateService)
local RebirthProgressionConfigs = require(
	ReplicatedStorage.Shared.Progression.RebirthProgressionConfigs
)
local RebirthProgressionRules = require(
	ReplicatedStorage.Shared.Progression.RebirthProgressionRules
)

local RebirthActionQuery = {}

function RebirthActionQuery.Get(player: Player)
	local state = RebirthStateService.Get(player)
	local eligibility = RebirthProgressionRules.EvaluateEligibility(
		state.Count,
		state.RunEarnings,
		RebirthProgressionConfigs.Eligibility
	)
	return {
		Allowed = eligibility.Allowed,
		Reason = eligibility.Reason,
		Count = state.Count,
		NextCount = eligibility.NextRebirthCount,
		RunEarnings = state.RunEarnings,
		RequiredRunEarnings = eligibility.RequiredRunEarnings,
		RemainingRunEarnings = eligibility.RemainingRunEarnings,
		CurrentBonuses = RebirthProgressionRules.ResolveBonuses(
			state.Count,
			RebirthProgressionConfigs.Bonuses
		),
		NextBonuses = RebirthProgressionRules.ResolveBonuses(
			eligibility.NextRebirthCount,
			RebirthProgressionConfigs.Bonuses
		),
	}
end

return RebirthActionQuery
