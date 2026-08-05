--[[
	职责：发送 Roblox AnalyticsService 原生的一次性和重复漏斗步骤。
	输入：Player、稳定漏斗名/步骤名；重复漏斗额外接收唯一 FunnelSessionId。
	输出：调用是否成功；Studio/未发布环境或服务异常时安全返回 false。
	内部算法：校验公共参数，再以 pcall 调用对应 AnalyticsService 方法。
	不负责：生成 SessionId、判断阶段是否完成、发送 GameAnalytics 事件或改变玩家状态。
]]

local AnalyticsService = game:GetService("AnalyticsService")

local GameAnalyticsConfig = require(script.Parent.GameAnalyticsConfig)

local RobloxFunnelGateway = {}

local STEP_NAMES = table.freeze({
	[1] = "Player Joined",
	[2] = "Save Ready",
	[3] = "Playable",
})

function RobloxFunnelGateway.LogSessionLoadStep(
	player: Player,
	funnelSessionId: string,
	step: number
): boolean
	local stepName = STEP_NAMES[step]
	if not stepName
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or type(funnelSessionId) ~= "string"
		or funnelSessionId == ""
	then
		return false
	end

	local succeeded = pcall(
		AnalyticsService.LogFunnelStepEvent,
		AnalyticsService,
		player,
		GameAnalyticsConfig.SessionLoadFunnelName,
		funnelSessionId,
		step,
		stepName
	)
	return succeeded
end

function RobloxFunnelGateway.LogRecurringStep(
	player: Player,
	funnelName: string,
	funnelSessionId: string,
	step: number,
	stepName: string
): boolean
	if typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or type(funnelName) ~= "string"
		or funnelName == ""
		or type(funnelSessionId) ~= "string"
		or funnelSessionId == ""
		or type(step) ~= "number"
		or step < 1
		or step % 1 ~= 0
		or type(stepName) ~= "string"
		or stepName == ""
	then
		return false
	end
	local succeeded = pcall(
		AnalyticsService.LogFunnelStepEvent,
		AnalyticsService,
		player,
		funnelName,
		funnelSessionId,
		step,
		stepName
	)
	return succeeded
end

function RobloxFunnelGateway.LogOnboardingStep(
	player: Player,
	step: number,
	stepName: string
): boolean
	if typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or type(step) ~= "number"
		or step < 1
		or step % 1 ~= 0
		or type(stepName) ~= "string"
		or stepName == ""
	then
		return false
	end
	local succeeded = pcall(
		AnalyticsService.LogOnboardingFunnelStepEvent,
		AnalyticsService,
		player,
		step,
		stepName
	)
	return succeeded
end

return table.freeze(RobloxFunnelGateway)
