--[[
	职责：定义群组奖励的跨端请求、奖励类型、状态和失败原因。
	输入/输出：无函数；服务端领取入口和未来客户端面板共同读取这些常量。
	内部算法：无；纯只读协议配置。
	不负责：群组成员校验、奖励配置、发放、存档或 UI。
]]

local CurrencyProtocol = require(script.Parent.Parent.Economy.CurrencyProtocol)

return table.freeze({
	RemoteName = "GroupRewardRequest",
	Types = table.freeze({
		Money = CurrencyProtocol.Types.Money,
		Diamond = CurrencyProtocol.Types.Diamond,
	}),
	RequestKinds = table.freeze({
		GetState = "GetState",
		Claim = "Claim",
	}),
	Statuses = table.freeze({
		Claimable = "Claimable",
		NotMember = "NotMember",
		Claimed = "Claimed",
	}),
	Reasons = table.freeze({
		PlayerDataNotReady = "PlayerDataNotReady",
		InvalidRequestKind = "InvalidRequestKind",
		ActionBusy = "ActionBusy",
		NotGroupMember = "NotGroupMember",
		RewardAlreadyClaimed = "RewardAlreadyClaimed",
		GroupCheckFailed = "GroupCheckFailed",
		InvalidRewardConfig = "InvalidRewardConfig",
		UnsupportedRewardType = "UnsupportedRewardType",
		RewardGrantFailed = "RewardGrantFailed",
	}),
})
