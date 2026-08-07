--[[
	职责：配置 Jeep 探险的时长、奖励和绕圈半径。
	输入：无。
	输出：JeepExpeditionService 使用的只读配置。
	不负责：探险状态、车辆移动、触发入口或钻石写入。
]]

return table.freeze({
	DurationSeconds = 60,
	RewardDiamonds = 10,
	OrbitRadius = 30,
})
