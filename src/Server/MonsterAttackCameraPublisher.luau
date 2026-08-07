--[[
	职责：向怪兽攻击的攻击者客户端发布出罐完成后的区域运镜命令。
	输入：目标 Player 与已通过协议校验的 FocusRegion command。
	输出：发布结果，或等待攻击者镜头完成的结果。
	不负责：判断攻击是否合法、查找目标 Plot 或播放相机动画。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterAttackCameraProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterAttackCameraProtocol
)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)

local MonsterAttackCameraPublisher = {}

export type Result = {
	Succeeded: boolean,
	Reason: string?,
}

local remote: RemoteEvent? = nil
local requestRemote: RemoteEvent? = nil
local requestConnection: RBXScriptConnection? = nil
local completedByPlayer: { [Player]: { [string]: { [number]: boolean } } } = setmetatable(
	{},
	{ __mode = "k" }
)

local function getRemote(): RemoteEvent
	if remote and remote.Parent then
		return remote
	end
	remote = ServerRemoteAccess.EnsureEvent(MonsterAttackCameraProtocol.RemoteName)
	return remote
end

local function getRequestRemote(): RemoteEvent
	if requestRemote and requestRemote.Parent then
		return requestRemote
	end
	requestRemote = ServerRemoteAccess.EnsureEvent(
		MonsterAttackCameraProtocol.RequestRemoteName
	)
	return requestRemote
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

function MonsterAttackCameraPublisher.Start()
	if requestConnection then
		return
	end
	getRemote()
	requestConnection = getRequestRemote().OnServerEvent:Connect(function(player, request)
		local valid, reason = MonsterAttackCameraProtocol.ValidateRequest(request)
		if not valid then
			warn("拒绝怪兽攻击区域运镜完成回执：", reason)
			return
		end
		if request.AttackerUserId ~= player.UserId then
			warn("拒绝非本人怪兽攻击区域运镜完成回执")
			return
		end
		markCompleted(player, request.AttackerSpawnPointId, request.CommandId)
	end)
	Players.PlayerRemoving:Connect(function(player)
		completedByPlayer[player] = nil
	end)
end

function MonsterAttackCameraPublisher.Publish(
	player: Player,
	command: MonsterAttackCameraProtocol.Command
): Result
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return { Succeeded = false, Reason = "AttackerUnavailable" }
	end
	local valid, reason = MonsterAttackCameraProtocol.Validate(command)
	if not valid then
		return { Succeeded = false, Reason = reason or "InvalidCameraCommand" }
	end
	if command.AttackerUserId ~= player.UserId then
		return { Succeeded = false, Reason = "AttackerIdentityMismatch" }
	end

	local published, publishError = pcall(function()
		getRemote():FireClient(player, command)
	end)
	if not published then
		warn("发布怪兽攻击区域运镜失败：", publishError)
		return { Succeeded = false, Reason = "CameraPublishFailed" }
	end
	return { Succeeded = true, Reason = nil }
end

function MonsterAttackCameraPublisher.WaitForCompletion(
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
			return { Succeeded = true, Reason = nil }
		end
		if isCancelled and isCancelled() then
			return { Succeeded = false, Reason = "Cancelled" }
		end
		local remaining = deadline - workspace:GetServerTimeNow()
		if remaining <= 0 then
			return { Succeeded = false, Reason = "CameraTransitionTimeout" }
		end
		task.wait(math.min(0.05, remaining))
	end
end

return MonsterAttackCameraPublisher
