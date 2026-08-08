--[[
	职责：保存载具管理 RemoteFunction 的稳定名称和请求种类。
	不负责：等级计算、货币结算、拥有关系、存档或 UI。
]]

return table.freeze({
	RemoteName = "VehicleManagementRequest",
	RequestKinds = table.freeze({
		GetState = "GetState",
		Upgrade = "Upgrade",
		Destroy = "Destroy",
	}),
})
