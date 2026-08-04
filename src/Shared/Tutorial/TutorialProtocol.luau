--[[
	职责：定义新手引导跨端合同中的稳定名称。
	输入/输出：无函数；只提供 RemoteFunction 与完成版本镜像 Attribute 名称。
	不负责：步骤计算、服务器校验、持久化或客户端表现。
]]

return table.freeze({
	SnapshotRemoteName = "TutorialSnapshot",
	CompletedVersionAttributeName = "TutorialCompletedVersion",
})
