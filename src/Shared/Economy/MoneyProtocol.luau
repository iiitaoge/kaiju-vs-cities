--[[
	职责：定义现金余额的跨端只读镜像协议。
	输入/输出：无函数；提供服务端写入与客户端监听共享的 Attribute 名称。
	内部算法：无；纯只读协议配置，不读取 Instance 或其他模块。
]]

return table.freeze({
	BalanceAttributeName = "MoneyBalance",
})
