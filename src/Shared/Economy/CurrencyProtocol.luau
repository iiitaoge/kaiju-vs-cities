--[[
	职责：定义游戏内可发放货币的稳定类型名称。
	输入/输出：无函数；服务端奖励、货币模块和客户端表现共同读取这些常量。
	内部算法：无；纯只读协议配置。
	不负责：余额、存档、发放、消费或 UI。
]]

local types = {
	Money = "Money",
	Diamond = "Diamond",
}

return table.freeze({
	Types = table.freeze(types),
})
