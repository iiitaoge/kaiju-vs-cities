--[[
	职责：向防守玩家发布怪兽出征的开始/结束通知，并提供当前进度状态补查。
	输入：防守 Player、攻击命令身份和服务端 StartedAt。
	输出：Remote 发布结果；查询返回该防守玩家当前未结束的开始 command。
	内部算法：构造协议 command → 校验 → FireClient，并按防守玩家保存当前 command。
	不负责：计算时长、执行攻击、显示 UI 或发布防守方决斗观看命令。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterExpeditionProgressProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionProgressProtocol
)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)

local MonsterExpeditionProgressPublisher = {}

export type Result = {
	Succeeded: boolean,
	Reason: string?,
}

local remote: RemoteEvent? = nil
local queryRemote: RemoteFunction? = nil
local activeByDefender: { [Player]: MonsterExpeditionProgressProtocol.StartedCommand } = setmetatable(
	{},
	{ __mode = "k" }
)

local function result(succeeded: boolean, reason: string?): Result
	return {
		Succeeded = succeeded,
		Reason = reason,
	}
end

local function getRemote(): RemoteEvent
	if remote and remote.Parent then
		return remote
	end
	remote = ServerRemoteAccess.EnsureEvent(MonsterExpeditionProgressProtocol.RemoteName)
	return remote
end

local function getQueryRemote(): RemoteFunction
	if queryRemote and queryRemote.Parent then
		return queryRemote
	end
	queryRemote = ServerRemoteAccess.EnsureFunction(
		MonsterExpeditionProgressProtocol.QueryRemoteName
	)
	return queryRemote
end

function MonsterExpeditionProgressPublisher.Start()
	getRemote()
	getQueryRemote().OnServerInvoke = function(player: Player)
		return {
			Succeeded = true,
			Command = activeByDefender[player],
		}
	end
end

local function publish(defender: Player, command: MonsterExpeditionProgressProtocol.Command): Result
	if typeof(defender) ~= "Instance"
		or not defender:IsA("Player")
		or defender.Parent ~= Players
	then
		return result(false, "DefenderUnavailable")
	end
	local valid, reason = MonsterExpeditionProgressProtocol.Validate(command)
	if not valid then
		return result(false, reason or "InvalidCommand")
	end
	local published, publishError = pcall(function()
		getRemote():FireClient(defender, command)
	end)
	if not published then
		warn("发布防守方出征进度失败：", publishError)
		return result(false, "ProgressPublishFailed")
	end
	return result(true, nil)
end

function MonsterExpeditionProgressPublisher.PublishStarted(
	defender: Player,
	commandId: number,
	attackerUserId: number,
	attackerSpawnPointId: string,
	startedAt: number
): Result
	local command: MonsterExpeditionProgressProtocol.StartedCommand = {
		Kind = MonsterExpeditionProgressProtocol.StartedKind,
		CommandId = commandId,
		AttackerUserId = attackerUserId,
		AttackerSpawnPointId = attackerSpawnPointId,
		StartedAt = startedAt,
	}
	local published = publish(defender, command)
	if published.Succeeded then
		activeByDefender[defender] = command
	end
	return published
end

function MonsterExpeditionProgressPublisher.PublishEnded(
	defender: Player,
	commandId: number,
	attackerUserId: number,
	attackerSpawnPointId: string
): Result
	local command: MonsterExpeditionProgressProtocol.EndedCommand = {
		Kind = MonsterExpeditionProgressProtocol.EndedKind,
		CommandId = commandId,
		AttackerUserId = attackerUserId,
		AttackerSpawnPointId = attackerSpawnPointId,
	}
	local valid, reason = MonsterExpeditionProgressProtocol.Validate(command)
	if not valid then
		return result(false, reason or "InvalidCommand")
	end
	local active = activeByDefender[defender]
	if active
		and active.CommandId == command.CommandId
		and active.AttackerUserId == command.AttackerUserId
		and active.AttackerSpawnPointId == command.AttackerSpawnPointId
	then
		activeByDefender[defender] = nil
	end
	return publish(defender, command)
end

return MonsterExpeditionProgressPublisher
