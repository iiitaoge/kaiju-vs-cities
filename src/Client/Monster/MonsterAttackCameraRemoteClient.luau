--[[
	职责：接收并校验服务器发布的怪兽攻击区域运镜命令，并回报镜头完成。
	输入：Observe 接收一个本地处理回调；Acknowledge 接收已完成的镜头命令。
	输出：RemoteEvent 连接或完成回执发送结果。
	不负责：查找目标 Plot、管理相机会话、决定运镜时长或改变怪兽状态。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterAttackCameraProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterAttackCameraProtocol
)

local MonsterAttackCameraRemoteClient = {}

local function getRemote(): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	local remote = remotes:WaitForChild(MonsterAttackCameraProtocol.RemoteName, 10)
	assert(
		remote and remote:IsA("RemoteEvent"),
		"找不到怪兽攻击区域运镜 RemoteEvent：" .. MonsterAttackCameraProtocol.RemoteName
	)
	return remote
end

local function getRequestRemote(): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	local remote = remotes:WaitForChild(
		MonsterAttackCameraProtocol.RequestRemoteName,
		10
	)
	assert(
		remote and remote:IsA("RemoteEvent"),
		"找不到怪兽攻击区域运镜请求 RemoteEvent："
			.. MonsterAttackCameraProtocol.RequestRemoteName
	)
	return remote
end

function MonsterAttackCameraRemoteClient.Observe(
	listener: (MonsterAttackCameraProtocol.Command) -> ()
): RBXScriptConnection
	assert(type(listener) == "function", "listener 必须是 function")
	return getRemote().OnClientEvent:Connect(function(command)
		local valid, reason = MonsterAttackCameraProtocol.Validate(command)
		if not valid then
			warn("拒绝怪兽攻击区域运镜命令：" .. (reason or "Unknown"))
			return
		end
		listener(command)
	end)
end

function MonsterAttackCameraRemoteClient.Acknowledge(
	command: MonsterAttackCameraProtocol.Command
): boolean
	if command.Kind ~= MonsterAttackCameraProtocol.FocusRegionKind
		and command.Kind ~= MonsterAttackCameraProtocol.FocusSoloRegionKind
	then
		return false
	end
	local request = {
		Kind = MonsterAttackCameraProtocol.TransitionCompletedKind,
		CommandId = command.CommandId,
		AttackerUserId = command.AttackerUserId,
		AttackerSpawnPointId = command.AttackerSpawnPointId,
	}
	local valid = MonsterAttackCameraProtocol.ValidateRequest(request)
	if not valid then
		return false
	end
	getRequestRemote():FireServer(request)
	return true
end

return MonsterAttackCameraRemoteClient
