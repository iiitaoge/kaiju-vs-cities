--[[
	职责：声明客户端可上报的低信任 UI 行为白名单。
	输入：IsKnownIntent 接收客户端 Intent 字符串。
	输出：稳定 Remote 名称、Intent 常量和白名单判断。
	内部算法：只做常量表查找。
	不负责：发送 Remote、校验业务状态、记录漏斗、金额、等级或服务器成功事实。
]]

local AnalyticsIntentProtocol = {}

local intents = table.freeze({
	MonsterManagementOpened = "MonsterManagementOpened",
	MonsterManagementClosed = "MonsterManagementClosed",
	MonsterUpgradeClicked = "MonsterUpgradeClicked",
	AttackStartClicked = "AttackStartClicked",
	AttackTargetSelected = "AttackTargetSelected",
	AttackCancelled = "AttackCancelled",
	AttackUnavailable = "AttackUnavailable",
	AttackValidationFailed = "AttackValidationFailed",
	RebirthOpened = "RebirthOpened",
	RebirthExecuteClicked = "RebirthExecuteClicked",
})

local known = {}
for _, intent in intents do
	known[intent] = true
end
table.freeze(known)

AnalyticsIntentProtocol.RemoteName = "AnalyticsIntent"
AnalyticsIntentProtocol.Intents = intents
AnalyticsIntentProtocol.MaxSubjectLength = 32
AnalyticsIntentProtocol.MaxReasonLength = 32

function AnalyticsIntentProtocol.IsKnownIntent(intent): boolean
	return type(intent) == "string" and known[intent] == true
end

return table.freeze(AnalyticsIntentProtocol)
