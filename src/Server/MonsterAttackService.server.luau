--[[
	职责：把两个正式攻击 RemoteFunction 适配到目标查询和攻击应用模块。
	输入：目标查询只接收 Player；命令接收 SpawnPointId、TargetPlayerId、EntryPoint。
	输出：稳定的 Succeeded/Reason/Targets 或 Succeeded/Reason/CommandId/Monster。
	内部算法：先做网络边界类型校验，再保护调用服务器权威业务模块。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerAttackTargetQuery = require(script.Parent.PlayerAttackTargetQuery)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerMonsterAttackApplication = require(script.Parent.PlayerMonsterAttackApplication)
local GameAnalyticsGateway = require(script.Parent.Analytics.GameAnalyticsGateway)
local SecurityAnalyticsAggregator = require(
	script.Parent.Analytics.SecurityAnalyticsAggregator
)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local TutorialProgressStateService = require(script.Parent.TutorialProgressStateService)
local MonsterAttackProtocol = require(ReplicatedStorage.Shared.Monster.MonsterAttackProtocol)
local ValueValidation = require(ReplicatedStorage.Shared.ValueValidation)

local targetQueryRemote = ServerRemoteAccess.EnsureFunction(
	MonsterAttackProtocol.TargetQueryRemoteName
)
local commandRemote = ServerRemoteAccess.EnsureFunction(MonsterAttackProtocol.CommandRemoteName)

targetQueryRemote.OnServerInvoke = function(player)
	if PlayerDataReadyService.Get(player).Status ~= "Ready" then
		return { Succeeded = false, Reason = "PlayerDataNotReady", Targets = {} }
	end
	local succeeded, responseOrError = xpcall(function()
		return PlayerAttackTargetQuery.Query(player)
	end, debug.traceback)
	if not succeeded then
		warn(string.format("查询攻击目标异常：%s (%s)", player.Name, tostring(responseOrError)))
		return { Succeeded = false, Reason = "ServerError", Targets = {} }
	end
	return responseOrError
end

commandRemote.OnServerInvoke = function(player, spawnPointId, targetPlayerId, entryPoint)
	if PlayerDataReadyService.Get(player).Status ~= "Ready" then
		return { Succeeded = false, Reason = "PlayerDataNotReady", CommandId = nil, Monster = nil }
	end
	if type(spawnPointId) ~= "string" or spawnPointId == "" then
		SecurityAnalyticsAggregator.Record(player, "MonsterAttack", "InvalidSpawnPointId")
		return { Succeeded = false, Reason = "InvalidSpawnPointId", CommandId = nil, Monster = nil }
	end
	if type(targetPlayerId) ~= "number"
		or targetPlayerId ~= targetPlayerId
		or math.abs(targetPlayerId) == math.huge
		or targetPlayerId % 1 ~= 0
		or targetPlayerId == 0 then
		SecurityAnalyticsAggregator.Record(player, "MonsterAttack", "InvalidTargetPlayerId")
		return { Succeeded = false, Reason = "InvalidTargetPlayerId", CommandId = nil, Monster = nil }
	end
	if not ValueValidation.IsFiniteVector3(entryPoint) then
		SecurityAnalyticsAggregator.Record(player, "MonsterAttack", "InvalidEntryPoint")
		return { Succeeded = false, Reason = "InvalidEntryPoint", CommandId = nil, Monster = nil }
	end

	local succeeded, responseOrError = xpcall(function()
		return PlayerMonsterAttackApplication.Execute(
			player,
			spawnPointId,
			targetPlayerId,
			entryPoint
		)
	end, debug.traceback)
	if not succeeded then
		warn(string.format(
			"提交怪兽攻击异常：%s/%s/%s (%s)",
			player.Name,
			spawnPointId,
			tostring(targetPlayerId),
			tostring(responseOrError)
		))
		return { Succeeded = false, Reason = "ServerError", CommandId = nil, Monster = nil }
	end
	if responseOrError.Succeeded then
		TutorialProgressStateService.Complete(player)
	else
		local reason = responseOrError.Reason or "Unknown"
		reason = string.match(reason, "^[^:]+") or "Unknown"
		GameAnalyticsGateway.LogDesign(
			player,
			"Gameplay:Attack:Rejected:" .. string.sub(reason, 1, 32)
		)
	end
	return responseOrError
end
