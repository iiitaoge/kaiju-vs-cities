--[[
	职责：保存载具箱子 RemoteFunction 的稳定名称和请求种类。
	不负责：价格、概率、随机、货币扣除、存档或 UI。
]]

return table.freeze({
	RemoteName = "VehicleCrateRequest",
	FeatureUnlockedAttributeName = "VehicleFeatureUnlocked",
	RequestKinds = table.freeze({
		GetState = "GetState",
		PurchaseDiamond = "PurchaseDiamond",
	}),
	DrawCounts = table.freeze({
		Single = 1,
		Five = 5,
	}),
})
