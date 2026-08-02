--[[
	职责：保存怪兽管理 Remote 的稳定名称和请求种类。
	不负责：请求执行、响应校验、状态转换或 UI 表现。
]]

return table.freeze({
	RemoteName = "MonsterManagementRequest",
	GetSnapshot = "GetSnapshot",
	Upgrade = "Upgrade",
})
