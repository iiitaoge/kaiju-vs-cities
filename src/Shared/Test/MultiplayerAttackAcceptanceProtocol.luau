--[[
	职责：保存多人攻击总验收临时控制通道的稳定名称和消息 Kind。
	输入：测试端读取常量。
	输出：只读协议常量。
	不负责：创建 Remote、执行攻击、保存测试状态或参与正式玩法网络。
]]

local kinds = table.freeze({
	ClientReady = "ClientReady",
	BeginScenario = "BeginScenario",
	ScenarioReady = "ScenarioReady",
	RequestAttack = "RequestAttack",
	AttackResponse = "AttackResponse",
	PresentationObserved = "PresentationObserved",
	EvidenceAccepted = "EvidenceAccepted",
	AcceptanceFinished = "AcceptanceFinished",
})

return table.freeze({
	RemoteName = "CodexMultiplayerAttackAcceptance",
	TestArgument = "MultiplayerAttackAcceptance",
	RequiredPlayerCount = 3,
	Kinds = kinds,
})
