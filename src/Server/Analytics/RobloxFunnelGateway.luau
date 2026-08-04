--[[
	职责：发送 Roblox AnalyticsService 原生的每局加载漏斗步骤。
	输入：Player、同一局唯一 FunnelSessionId、1~3 的步骤编号。
	输出：调用是否成功；Studio/未发布环境或服务异常时安全返回 false。
	内部算法：把固定步骤映射为稳定名称，并以 pcall 调用 LogFunnelStepEvent。
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

return table.freeze(RobloxFunnelGateway)
