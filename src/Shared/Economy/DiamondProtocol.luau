--[[
	职责：定义钻石余额的跨端只读镜像协议。
	输入/输出：无函数；服务端写入、客户端监听共享 Attribute 名称。
	内部算法：无；纯只读协议配置。
	不负责：钻石计算、发放、消费、存档或 UI。
]]

return table.freeze({
	BalanceAttributeName = "DiamondBalance",
})
