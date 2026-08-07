--[[
	职责：定义防守方出征进度条的跨端事件与状态查询合同。
	输入：服务器发送的出征开始/结束 command，客户端发起的当前状态查询。
	输出：合法性结果、稳定字段定义和 Remote 名称。
	不负责：计时、UI、攻击执行或决斗观看按钮。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local MonsterExpeditionProgressProtocol = {}

MonsterExpeditionProgressProtocol.RemoteName = "MonsterExpeditionProgressPresentation"
MonsterExpeditionProgressProtocol.QueryRemoteName = "MonsterExpeditionProgressQuery"
MonsterExpeditionProgressProtocol.StartedKind = "ExpeditionStarted"
MonsterExpeditionProgressProtocol.EndedKind = "ExpeditionEnded"

export type StartedCommand = {
	Kind: "ExpeditionStarted",
	CommandId: number,
	AttackerUserId: number,
	AttackerSpawnPointId: string,
	StartedAt: number,
}

export type EndedCommand = {
	Kind: "ExpeditionEnded",
	CommandId: number,
	AttackerUserId: number,
	AttackerSpawnPointId: string,
}

export type Command = StartedCommand | EndedCommand

local function isPositiveInteger(value): boolean
	return type(value) == "number"
		and ValueValidation.IsFiniteNumber(value)
		and value % 1 == 0
		and value > 0
end

function MonsterExpeditionProgressProtocol.Validate(command): (boolean, string?)
	if type(command) ~= "table" then
		return false, "InvalidCommand"
	end
	if command.Kind ~= MonsterExpeditionProgressProtocol.StartedKind
		and command.Kind ~= MonsterExpeditionProgressProtocol.EndedKind
	then
		return false, "InvalidKind"
	end
	if not isPositiveInteger(command.CommandId) then
		return false, "InvalidCommandId"
	end
	if not isPositiveInteger(command.AttackerUserId) then
		return false, "InvalidAttackerUserId"
	end
	if not ValueValidation.IsNonEmptyString(command.AttackerSpawnPointId) then
		return false, "InvalidAttackerSpawnPointId"
	end
	if command.Kind == MonsterExpeditionProgressProtocol.StartedKind
		and not ValueValidation.IsFiniteNumber(command.StartedAt)
	then
		return false, "InvalidStartedAt"
	end
	return true, nil
end

return table.freeze(MonsterExpeditionProgressProtocol)
