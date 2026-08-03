--[[
	职责：定义 Studio 测试删档跨端协议名称。
	输入/输出：无函数；提供服务端与客户端共享的 RemoteName。
	内部算法：无；纯只读协议配置，不读取 Instance 或其他模块。
]]

return table.freeze({
	RemoteName = "StudioSaveReset",
})
