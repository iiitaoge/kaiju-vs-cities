--[[
	职责：把客户端怪兽管理请求适配为稳定函数。

	输入：GetSnapshot/Upgrade/UpgradeToMax 接收 SpawnPointId。
	输出：Succeeded、Reason、Snapshot；网络或响应异常转换为稳定失败。
	内部算法：调用唯一 MonsterManagementRequest RemoteFunction 并验证响应外形。

	不负责：状态机、GUI、重试策略或攻击选择。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManagementProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterManagementProtocol
)

local MonsterManagementRemoteClient = {}
local remote: RemoteFunction? = nil

local function getRemote(): RemoteFunction
	if remote and remote.Parent then
		return remote
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	local instance = remotes:WaitForChild(MonsterManagementProtocol.RemoteName, 10)
	assert(instance and instance:IsA("RemoteFunction"), "找不到怪兽管理 RemoteFunction")
	remote = instance
	return instance
end

local function request(requestKind: string, spawnPointId: string)
	local succeeded, responseOrError = pcall(function()
		return getRemote():InvokeServer(requestKind, spawnPointId)
	end)
	if not succeeded then
		warn(string.format(
			"怪兽管理 Remote 失败：%s/%s (%s)",
			requestKind,
			spawnPointId,
			tostring(responseOrError)
		))
		return { Succeeded = false, Reason = "RequestFailed", Snapshot = nil }
	end
	if type(responseOrError) ~= "table" or type(responseOrError.Succeeded) ~= "boolean" then
		return { Succeeded = false, Reason = "InvalidServerResponse", Snapshot = nil }
	end
	return responseOrError
end

function MonsterManagementRemoteClient.GetSnapshot(spawnPointId: string)
	return request(MonsterManagementProtocol.GetSnapshot, spawnPointId)
end

function MonsterManagementRemoteClient.Upgrade(spawnPointId: string)
	return request(MonsterManagementProtocol.Upgrade, spawnPointId)
end

function MonsterManagementRemoteClient.UpgradeToMax(spawnPointId: string)
	return request(MonsterManagementProtocol.UpgradeToMax, spawnPointId)
end

return MonsterManagementRemoteClient
