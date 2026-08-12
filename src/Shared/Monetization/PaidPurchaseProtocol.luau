--[[
	职责：保存付费准备 Remote 和收据结果 RemoteEvent 的稳定协议。
	不负责：ProductId、收据处理、商品发放或 UI。
]]

return table.freeze({
	RequestRemoteName = "PaidPurchaseRequest",
	ResultRemoteName = "PaidPurchaseResult",
	PaidRandomItemsAllowedAttributeName = "PaidRandomItemsAllowed",
	RequestKinds = table.freeze({
		PrepareMonsterUpgrade = "PrepareMonsterUpgrade",
		CancelMonsterUpgrade = "CancelMonsterUpgrade",
	}),
	ResultKinds = table.freeze({
		PurchaseGranted = "PurchaseGranted",
	}),
})
