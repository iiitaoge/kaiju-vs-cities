--[[
	职责：把 MonsterManagementRequest RemoteFunction 适配到服务器管理协调器。

	输入：Player、GetSnapshot/Upgrade、SpawnPointId。
	输出：协调器的 Succeeded、Reason、Snapshot。
	内部算法：通过 ServerRemoteAccess 获取唯一 RemoteFunction、校验基础输入并保护调用。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManagementCoordinator = require(script.Parent.MonsterManagementCoordinator)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerJourneyAnalyticsCoordinator = require(
	script.Parent.Analytics.PlayerJourneyAnalyticsCoordinator
)
local SecurityAnalyticsAggregator = require(
	script.Parent.Analytics.SecurityAnalyticsAggregator
)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local MonsterManagementProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterManagementProtocol
)

local remote = ServerRemoteAccess.EnsureFunction(MonsterManagementProtocol.RemoteName)

remote.OnServerInvoke = function(player, requestKind, spawnPointId)
	if PlayerDataReadyService.Get(player).Status ~= "Ready" then
		return { Succeeded = false, Reason = "PlayerDataNotReady", Snapshot = nil }
	end
	if type(spawnPointId) ~= "string" or spawnPointId == "" then
		SecurityAnalyticsAggregator.Record(player, "MonsterManagement", "InvalidSpawnPointId")
		return { Succeeded = false, Reason = "InvalidSpawnPointId", Snapshot = nil }
	end
	if requestKind ~= MonsterManagementProtocol.GetSnapshot
		and requestKind ~= MonsterManagementProtocol.Upgrade then
		SecurityAnalyticsAggregator.Record(player, "MonsterManagement", "InvalidRequest")
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
	if requestKind == MonsterManagementProtocol.Upgrade
		and not responseOrError.Succeeded
	then
		PlayerJourneyAnalyticsCoordinator.RecordMonsterUpgradeRejected(
			player,
			spawnPointId,
			responseOrError.Reason
		)
	end
	return responseOrError
end
