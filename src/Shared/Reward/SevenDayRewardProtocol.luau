--[[
	职责：定义七日奖励跨端请求、状态和失败原因的稳定名称。
	输入/输出：无函数；服务端 RemoteFunction 与未来客户端 UI 共同读取这些常量。
	内部算法：无；纯只读协议配置。
	不负责：奖励配置、倒计时计算、发奖、存档或 UI 实例。
]]

return table.freeze({
	RemoteName = "SevenDayRewardRequest",
	RequestKinds = table.freeze({
		GetState = "GetState",
		Claim = "Claim",
	}),
	Statuses = table.freeze({
		Claimable = "Claimable",
		Cooldown = "Cooldown",
		Completed = "Completed",
	}),
	Reasons = table.freeze({
		PlayerDataNotReady = "PlayerDataNotReady",
		InvalidRequestKind = "InvalidRequestKind",
		ActionBusy = "ActionBusy",
		RewardCooldown = "RewardCooldown",
		RewardCompleted = "RewardCompleted",
		InvalidRewardConfig = "InvalidRewardConfig",
		UnsupportedRewardType = "UnsupportedRewardType",
	}),
})
