--[[
	职责：集中保存单次出征异常兜底和单场怪兽决斗的硬时间边界。
	输入/输出：调用方读取不可变秒数。
	不负责：启动计时器、取消移动、判断胜负或回城。
]]

return table.freeze({
	ExpeditionDuration = 30,
	DuelResolutionDuration = 4,
	DuelWatchdogDuration = 10,
})
