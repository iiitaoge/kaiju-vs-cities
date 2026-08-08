--[[
	职责：配置载具战斗的公共时间参数。
	输入：无。
	输出：VehicleBattleService 使用的只读配置。
	不负责：载具属性、战斗胜负或战斗状态。
]]

return table.freeze({
	AttackIntervalSeconds = 10,
})
