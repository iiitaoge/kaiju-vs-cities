--[[
	职责：保存服务器房屋收入交互的纯规则参数。
	输入：无。
	输出：领取冷却、角色位置复制宽限和重试间隔。
	不负责：不读取玩家状态、不验证位置、不发放收入。
]]

return table.freeze({
	RewardCooldown = 0.1,
	PositionSyncGraceSeconds = 0.35,
	PositionSyncRetrySeconds = 0.05,
})
