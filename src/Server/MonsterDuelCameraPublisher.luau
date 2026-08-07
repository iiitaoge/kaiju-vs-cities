--[[
	职责：发布决斗镜头命令，并把防守玩家的镜头请求交给决斗场景协调器。
	输入：目标 Player、已构造的协议命令，或客户端 Toggle 请求。
	输出：发布结果、攻击方镜头完成等待结果；非法请求只记录并丢弃。
	不负责：判断玩家是否属于某场决斗、创建场景或直接操作 CurrentCamera。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterDuelCameraProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterDuelCameraProtocol
)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)

local MonsterDuelCameraPublisher = {}

export type Result = {
	Succeeded: boolean,
	Reason: string?,
}

local presentationRemote: RemoteEvent? = nil
local requestConnection: RBXScriptConnection? = nil
local requestHandler: ((Player, MonsterDuelCameraProtocol.ToggleRequest) -> ())? = nil
local nextCommandId = 0
local completedByPlayer: { [Player]: { [string]: { [number]: boolean } } } = setmetatable(
	{},
	{ __mode = "k" }
)

local function result(succeeded: boolean, reason: string?): Result
	return {
		Succeeded = succeeded,
		Reason = reason,
	}
end

local function getPresentationRemote(): RemoteEvent
	if presentationRemote and presentationRemote.Parent then
		return presentationRemote
	end
	presentationRemote = ServerRemoteAccess.EnsureEvent(
		MonsterDuelCameraProtocol.RemoteName
	)
	return presentationRemote
end

local function getRequestRemote(): RemoteEvent
	return ServerRemoteAccess.EnsureEvent(MonsterDuelCameraProtocol.RequestRemoteName)
end

local function markCompleted(
	player: Player,
	spawnPointId: string,
	commandId: number
)
	local bySpawnPoint = completedByPlayer[player]
	if not bySpawnPoint then
		bySpawnPoint = {}
		completedByPlayer[player] = bySpawnPoint
	end
	local byCommand = bySpawnPoint[spawnPointId]
	if not byCommand then
		byCommand = {}
		bySpawnPoint[spawnPointId] = byCommand
	end
	byCommand[commandId] = true
end

local function takeCompleted(
	player: Player,
	spawnPointId: string,
	commandId: number
): boolean
	local bySpawnPoint = completedByPlayer[player]
	local byCommand = bySpawnPoint and bySpawnPoint[spawnPointId]
	if not byCommand or not byCommand[commandId] then
		return false
	end
	byCommand[commandId] = nil
	if next(byCommand) == nil then
		bySpawnPoint[spawnPointId] = nil
	end
	if next(bySpawnPoint) == nil then
		completedByPlayer[player] = nil
	end
	return true
end

function MonsterDuelCameraPublisher.NextCommandId(): number
	nextCommandId += 1
	return nextCommandId
end

function MonsterDuelCameraPublisher.Start(
	onRequest: (Player, MonsterDuelCameraProtocol.ToggleRequest) -> ()
)
	assert(type(onRequest) == "function", "onRequest 必须是 function")
	if requestConnection then
		return
	end
	requestHandler = onRequest
	getPresentationRemote()
	requestConnection = getRequestRemote().OnServerEvent:Connect(function(
		player,
		request
	)
		local valid, reason = MonsterDuelCameraProtocol.ValidateRequest(request)
		if not valid then
			warn("拒绝怪兽决斗镜头请求：", reason)
			return
		end
		if player.Parent ~= Players then
			return
		end
		if request.Kind == MonsterDuelCameraProtocol.TransitionCompletedKind then
			if request.AttackerUserId ~= player.UserId then
				warn("拒绝非本人攻击方决斗镜头完成回执")
				return
			end
			markCompleted(player, request.AttackerSpawnPointId, request.CommandId)
			return
		end
		local handler = requestHandler
		if handler then
			handler(player, request)
		end
	end)
end

function MonsterDuelCameraPublisher.Publish(
	player: Player,
	command: MonsterDuelCameraProtocol.Command
): Result
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return result(false, "PlayerUnavailable")
	end
	local valid, reason = MonsterDuelCameraProtocol.ValidateCommand(command)
	if not valid then
		return result(false, reason or "InvalidCommand")
	end
	local published, publishError = pcall(function()
		getPresentationRemote():FireClient(player, command)
	end)
	if not published then
		warn("发布怪兽决斗镜头命令失败：", publishError)
		return result(false, "CameraPublishFailed")
	end
	return result(true, nil)
end

function MonsterDuelCameraPublisher.WaitForCompletion(
	player: Player,
	spawnPointId: string,
	commandId: number,
	timeout: number,
	isCancelled: (() -> boolean)?
): Result
	assert(player:IsA("Player"), "player 必须是 Player")
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 无效")
	assert(type(commandId) == "number" and commandId > 0, "commandId 无效")
	assert(type(timeout) == "number" and timeout > 0, "timeout 必须大于 0")
	local deadline = workspace:GetServerTimeNow() + timeout
	while true do
		if takeCompleted(player, spawnPointId, commandId) then
			return result(true, nil)
		end
		if isCancelled and isCancelled() then
			return result(false, "Cancelled")
		end
		local remaining = deadline - workspace:GetServerTimeNow()
		if remaining <= 0 then
			return result(false, "CameraTransitionTimeout")
		end
		task.wait(math.min(0.05, remaining))
	end
end

return MonsterDuelCameraPublisher
