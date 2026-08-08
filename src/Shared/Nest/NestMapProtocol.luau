--[[
	职责：保存巢穴 Map RemoteFunction 的稳定名称和请求种类。
	不负责：巢穴状态、派遣、召回、镜头或 UI。
]]

return table.freeze({
	RemoteName = "NestMapRequest",
	RequestKinds = table.freeze({
		GetState = "GetState",
		Dispatch = "Dispatch",
		Recall = "Recall",
	}),
})
