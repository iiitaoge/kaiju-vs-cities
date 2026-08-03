--[[
	职责：保存八人容量验收的稳定启动参数。
	输入：测试启动端和服务端 Bootstrap 读取常量。
	输出：只读测试参数和玩家数量。
	内部算法：无；仅提供跨边界共享常量。
	不负责：创建玩家、分配 Plot、查询攻击目标或结束测试会话。
]]

return table.freeze({
	TestArgument = "EightPlayerCapacityAcceptance",
	RequiredPlayerCount = 8,
})
