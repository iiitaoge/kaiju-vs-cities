--[[
	职责：把 MonsterManagementRequest RemoteFunction 适配到服务器管理协调器。

	输入：Player、GetSnapshot/Upgrade、SpawnPointId。
	输出：协调器的 Succeeded、Reason、Snapshot。
	内部算法：创建唯一 RemoteFunction、校验基础输入、保护调用并返回稳定错误。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManagementCoordinator = require(script.Parent.MonsterManagementCoordinator)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local MonsterManagementProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterManagementProtocol
)

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end
assert(remotes:IsA("Folder"), "ReplicatedStorage.Remotes 必须是 Folder")

local existing = remotes:FindFirstChild(MonsterManagementProtocol.RemoteName)
if existing then
	assert(existing:IsA("RemoteFunction"), MonsterManagementProtocol.RemoteName .. " 必须是 RemoteFunction")
else
	existing = Instance.new("RemoteFunction")
	existing.Name = MonsterManagementProtocol.RemoteName
	existing.Parent = remotes
end
local remote = existing :: RemoteFunction

remote.OnServerInvoke = function(player, requestKind, spawnPointId)
	if PlayerDataReadyService.Get(player).Status ~= "Ready" then
		return { Succeeded = false, Reason = "PlayerDataNotReady", Snapshot = nil }
	end
	if type(spawnPointId) ~= "string" or spawnPointId == "" then
		return { Succeeded = false, Reason = "InvalidSpawnPointId", Snapshot = nil }
	end
	if requestKind ~= MonsterManagementProtocol.GetSnapshot
		and requestKind ~= MonsterManagementProtocol.Upgrade then
		return { Succeeded = false, Reason = "InvalidRequest", Snapshot = nil }
	end

	local succeeded, responseOrError = xpcall(function()
		if requestKind == MonsterManagementProtocol.GetSnapshot then
			return MonsterManagementCoordinator.Query(player, spawnPointId)
		end
		return MonsterManagementCoordinator.Upgrade(player, spawnPointId)
	end, debug.traceback)
	if not succeeded then
		warn(string.format(
			"怪兽管理请求异常：%s/%s/%s (%s)",
			player.Name,
			tostring(requestKind),
			spawnPointId,
			tostring(responseOrError)
		))
		return { Succeeded = false, Reason = "ServerError", Snapshot = nil }
	end
	return responseOrError
end
