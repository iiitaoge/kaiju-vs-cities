--[[
	职责：把正式攻击的两个 RemoteFunction 适配为稳定客户端函数。
	输入：QueryTargets 无业务参数；RequestAttack 接收 SpawnPointId、目标 Player 和落点。
	输出：稳定成功/失败响应；网络或响应外形异常转换为明确 Reason。
	不负责：状态机、目标缓存、相机、输入监听或本地领地校验。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterAttackProtocol = require(ReplicatedStorage.Shared.Monster.MonsterAttackProtocol)

local MonsterAttackRemoteClient = {}
local remotesByName: { [string]: RemoteFunction } = {}

local function getRemote(name: string): RemoteFunction
	local cached = remotesByName[name]
	if cached and cached.Parent then
		return cached
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	local instance = remotes:WaitForChild(name, 10)
	assert(instance and instance:IsA("RemoteFunction"), "找不到攻击 RemoteFunction：" .. name)
	remotesByName[name] = instance
	return instance
end

function MonsterAttackRemoteClient.QueryTargets()
	local succeeded, responseOrError = pcall(function()
		return getRemote(MonsterAttackProtocol.TargetQueryRemoteName):InvokeServer()
	end)
	if not succeeded then
		warn("查询攻击目标 Remote 失败：", responseOrError)
		return { Succeeded = false, Reason = "RequestFailed", Targets = {} }
	end
	if type(responseOrError) ~= "table"
		or type(responseOrError.Succeeded) ~= "boolean"
		or type(responseOrError.Targets) ~= "table" then
		return { Succeeded = false, Reason = "InvalidServerResponse", Targets = {} }
	end
	return responseOrError
end

function MonsterAttackRemoteClient.RequestAttack(
	spawnPointId: string,
	targetPlayer: Player,
	entryPoint: Vector3
)
	local succeeded, responseOrError = pcall(function()
		return getRemote(MonsterAttackProtocol.CommandRemoteName):InvokeServer(
			spawnPointId,
			targetPlayer.UserId,
			entryPoint
		)
	end)
	if not succeeded then
		warn("提交怪兽攻击 Remote 失败：", responseOrError)
		return { Succeeded = false, Reason = "RequestFailed", CommandId = nil, Monster = nil }
	end
	if type(responseOrError) ~= "table" or type(responseOrError.Succeeded) ~= "boolean" then
		return {
			Succeeded = false,
			Reason = "InvalidServerResponse",
			CommandId = nil,
			Monster = nil,
		}
	end
	if responseOrError.CommandId ~= nil and type(responseOrError.CommandId) ~= "number" then
		return {
			Succeeded = false,
			Reason = "InvalidServerResponse",
			CommandId = nil,
			Monster = nil,
		}
	end
	if responseOrError.Monster ~= nil
		and (typeof(responseOrError.Monster) ~= "Instance"
			or not responseOrError.Monster:IsA("Model")) then
		return {
			Succeeded = false,
			Reason = "InvalidServerResponse",
			CommandId = nil,
			Monster = nil,
		}
	end
	return responseOrError
end

return MonsterAttackRemoteClient
