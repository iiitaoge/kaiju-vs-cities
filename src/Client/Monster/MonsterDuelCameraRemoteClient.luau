--[[
	职责：接收决斗镜头命令，并向服务器发送防守方观看请求。
	输入：Observe 的本地监听器，或 DuelId/Enabled 请求。
	输出：已校验的命令回调和请求发送结果。
	不负责：决定玩家角色、显示按钮或直接操作 CurrentCamera。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterDuelCameraProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterDuelCameraProtocol
)

local MonsterDuelCameraRemoteClient = {}

local function getRemotes(): Folder
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	return remotes
end

local function getPresentationRemote(): RemoteEvent
	local remote = getRemotes():WaitForChild(
		MonsterDuelCameraProtocol.RemoteName,
		10
	)
	assert(
		remote and remote:IsA("RemoteEvent"),
		"找不到怪兽决斗镜头 RemoteEvent：" .. MonsterDuelCameraProtocol.RemoteName
	)
	return remote
end

local function getRequestRemote(): RemoteEvent
	local remote = getRemotes():WaitForChild(
		MonsterDuelCameraProtocol.RequestRemoteName,
		10
	)
	assert(
		remote and remote:IsA("RemoteEvent"),
		"找不到怪兽决斗镜头请求 RemoteEvent：" .. MonsterDuelCameraProtocol.RequestRemoteName
	)
	return remote
end

function MonsterDuelCameraRemoteClient.Observe(
	listener: (MonsterDuelCameraProtocol.Command) -> ()
): RBXScriptConnection
	assert(type(listener) == "function", "listener 必须是 function")
	return getPresentationRemote().OnClientEvent:Connect(function(command)
		local valid, reason = MonsterDuelCameraProtocol.ValidateCommand(command)
		if not valid then
			warn("拒绝怪兽决斗镜头命令：", reason)
			return
		end
		listener(command)
	end)
end

function MonsterDuelCameraRemoteClient.RequestToggle(
	duelId: string,
	enabled: boolean
): boolean
	local request = {
		Kind = MonsterDuelCameraProtocol.ToggleKind,
		DuelId = duelId,
		Enabled = enabled,
	}
	local valid = MonsterDuelCameraProtocol.ValidateRequest(request)
	if not valid then
		return false
	end
	getRequestRemote():FireServer(request)
	return true
end

function MonsterDuelCameraRemoteClient.Acknowledge(
	command: MonsterDuelCameraProtocol.Command
): boolean
	if command.Kind ~= MonsterDuelCameraProtocol.FocusKind
		or command.Role ~= "Attacker" then
		return false
	end
	local request = {
		Kind = MonsterDuelCameraProtocol.TransitionCompletedKind,
		CommandId = command.CommandId,
		DuelId = command.DuelId,
		Role = "Attacker",
		AttackerUserId = command.AttackerUserId,
		AttackerSpawnPointId = command.AttackerSpawnPointId,
		DefenderUserId = command.DefenderUserId,
	}
	local valid = MonsterDuelCameraProtocol.ValidateRequest(request)
	if not valid then
		return false
	end
	getRequestRemote():FireServer(request)
	return true
end

return MonsterDuelCameraRemoteClient
