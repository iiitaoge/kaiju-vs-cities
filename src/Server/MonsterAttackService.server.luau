--[[
	职责：把目标查询、玩家攻击和单人空地攻击 RemoteFunction 适配到权威应用模块。
	输入：目标查询只接收 Player；玩家命令接收目标 UserId；单人命令只接收 SpawnPointId 和 EntryPoint。
	输出：稳定的 Succeeded/Reason/Targets 或 Succeeded/Reason/CommandId/Monster。
	内部算法：先做网络边界类型校验，再保护调用服务器权威业务模块。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugLog = require(ReplicatedStorage.Shared.DebugLog)
local PlayerAttackTargetQuery = require(script.Parent.PlayerAttackTargetQuery)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerMonsterAttackApplication = require(script.Parent.PlayerMonsterAttackApplication)
local PlayerSoloMonsterAttackApplication = require(
	script.Parent.PlayerSoloMonsterAttackApplication
)
local DefenseMonsterSpawnPointStateService = require(
	script.Parent.DefenseMonsterSpawnPointStateService
)
local GameAnalyticsGateway = require(script.Parent.Analytics.GameAnalyticsGateway)
local PlayerJourneyAnalyticsCoordinator = require(
	script.Parent.Analytics.PlayerJourneyAnalyticsCoordinator
)
local SecurityAnalyticsAggregator = require(
	script.Parent.Analytics.SecurityAnalyticsAggregator
)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local TutorialProgressStateService = require(script.Parent.TutorialProgressStateService)
local MonsterAttackProtocol = require(ReplicatedStorage.Shared.Monster.MonsterAttackProtocol)
local ValueValidation = require(ReplicatedStorage.Shared.ValueValidation)

local attackCoordinateLog = DebugLog.Create("AttackSelectionCoordinates")

local function advanceTutorialAfterAttack(player: Player)
	if DefenseMonsterSpawnPointStateService.Get(player, "DM-R1").Built then
		TutorialProgressStateService.Complete(player)
	else
		TutorialProgressStateService.MarkAttackCompleted(player)
	end
end

local function vector3Text(value: Vector3): string
	return string.format("(%.2f,%.2f,%.2f)", value.X, value.Y, value.Z)
end

local targetQueryRemote = ServerRemoteAccess.EnsureFunction(
	MonsterAttackProtocol.TargetQueryRemoteName
)
local commandRemote = ServerRemoteAccess.EnsureFunction(MonsterAttackProtocol.CommandRemoteName)
local soloCommandRemote = ServerRemoteAccess.EnsureFunction(
	MonsterAttackProtocol.SoloCommandRemoteName
)

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
	if responseOrError.Succeeded then
		PlayerJourneyAnalyticsCoordinator.RecordAttackTargetsLoaded(
			player,
			#responseOrError.Targets
		)
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
	attackCoordinateLog(
		"[SERVER_REQUEST]",
		"mode=Player",
		"serverTime=" .. string.format("%.2f", workspace:GetServerTimeNow()),
		string.format("player=%s:%d", player.Name, player.UserId),
		"spawn=" .. spawnPointId,
		"targetUserId=" .. tostring(targetPlayerId),
		"entryPoint=" .. vector3Text(entryPoint)
	)
	PlayerJourneyAnalyticsCoordinator.RecordAttackRequested(player, spawnPointId)

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
		attackCoordinateLog(
			"[SERVER_RESULT]",
			"mode=Player",
			"succeeded=false",
			"reason=ServerError",
			"entryPoint=" .. vector3Text(entryPoint)
		)
		return { Succeeded = false, Reason = "ServerError", CommandId = nil, Monster = nil }
	end
	if responseOrError.Succeeded then
		PlayerJourneyAnalyticsCoordinator.RecordAttackAccepted(player, spawnPointId)
		advanceTutorialAfterAttack(player)
	else
		local reason = responseOrError.Reason or "Unknown"
		PlayerJourneyAnalyticsCoordinator.RecordAttackRejected(
			player,
			spawnPointId,
			reason
		)
		reason = string.match(reason, "^[^:]+") or "Unknown"
		GameAnalyticsGateway.LogDesign(
			player,
			"Gameplay:Attack:Rejected:" .. string.sub(reason, 1, 32)
		)
	end
	attackCoordinateLog(
		"[SERVER_RESULT]",
		"mode=Player",
		"serverTime=" .. string.format("%.2f", workspace:GetServerTimeNow()),
		"succeeded=" .. tostring(responseOrError.Succeeded),
		"reason=" .. tostring(responseOrError.Reason),
		"commandId=" .. tostring(responseOrError.CommandId),
		"entryPoint=" .. vector3Text(entryPoint)
	)
	return responseOrError
end

soloCommandRemote.OnServerInvoke = function(player, spawnPointId, entryPoint)
	if PlayerDataReadyService.Get(player).Status ~= "Ready" then
		return { Succeeded = false, Reason = "PlayerDataNotReady", CommandId = nil, Monster = nil }
	end
	if type(spawnPointId) ~= "string" or spawnPointId == "" then
		SecurityAnalyticsAggregator.Record(player, "SoloMonsterAttack", "InvalidSpawnPointId")
		return { Succeeded = false, Reason = "InvalidSpawnPointId", CommandId = nil, Monster = nil }
	end
	if not ValueValidation.IsFiniteVector3(entryPoint) then
		SecurityAnalyticsAggregator.Record(player, "SoloMonsterAttack", "InvalidEntryPoint")
		return { Succeeded = false, Reason = "InvalidEntryPoint", CommandId = nil, Monster = nil }
	end
	attackCoordinateLog(
		"[SERVER_REQUEST]",
		"mode=Solo",
		"serverTime=" .. string.format("%.2f", workspace:GetServerTimeNow()),
		string.format("player=%s:%d", player.Name, player.UserId),
		"spawn=" .. spawnPointId,
		"entryPoint=" .. vector3Text(entryPoint)
	)
	PlayerJourneyAnalyticsCoordinator.RecordAttackRequested(player, spawnPointId)

	local succeeded, responseOrError = xpcall(function()
		return PlayerSoloMonsterAttackApplication.Execute(
			player,
			spawnPointId,
			entryPoint
		)
	end, debug.traceback)
	if not succeeded then
		warn(string.format(
			"提交单人怪兽攻击异常：%s/%s (%s)",
			player.Name,
			spawnPointId,
			tostring(responseOrError)
		))
		attackCoordinateLog(
			"[SERVER_RESULT]",
			"mode=Solo",
			"succeeded=false",
			"reason=ServerError",
			"entryPoint=" .. vector3Text(entryPoint)
		)
		return { Succeeded = false, Reason = "ServerError", CommandId = nil, Monster = nil }
	end
	if responseOrError.Succeeded then
		PlayerJourneyAnalyticsCoordinator.RecordAttackAccepted(player, spawnPointId)
		advanceTutorialAfterAttack(player)
		GameAnalyticsGateway.LogDesign(
			player,
			"Gameplay:SoloAttack:Accepted:" .. spawnPointId
		)
	else
		local reason = responseOrError.Reason or "Unknown"
		PlayerJourneyAnalyticsCoordinator.RecordAttackRejected(
			player,
			spawnPointId,
			reason
		)
		GameAnalyticsGateway.LogDesign(
			player,
			"Gameplay:SoloAttack:Rejected:" .. string.sub(reason, 1, 32)
		)
	end
	attackCoordinateLog(
		"[SERVER_RESULT]",
		"mode=Solo",
		"serverTime=" .. string.format("%.2f", workspace:GetServerTimeNow()),
		"succeeded=" .. tostring(responseOrError.Succeeded),
		"reason=" .. tostring(responseOrError.Reason),
		"commandId=" .. tostring(responseOrError.CommandId),
		"entryPoint=" .. vector3Text(entryPoint)
	)
	return responseOrError
end
