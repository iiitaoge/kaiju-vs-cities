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
local MonsterAttackProtocol = require(ReplicatedStorage.Shared.Monster.MonsterAttackProtocol)

local function ensureRemote(name: string): RemoteFunction
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	assert(remotes:IsA("Folder"), "ReplicatedStorage.Remotes 必须是 Folder")

	local existing = remotes:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteFunction"), name .. " 必须是 RemoteFunction")
		return existing
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local function isFiniteVector3(value): boolean
	return typeof(value) == "Vector3"
		and value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < math.huge
		and math.abs(value.Y) < math.huge
		and math.abs(value.Z) < math.huge
end

local targetQueryRemote = ensureRemote(MonsterAttackProtocol.TargetQueryRemoteName)
local commandRemote = ensureRemote(MonsterAttackProtocol.CommandRemoteName)

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
		return { Succeeded = false, Reason = "InvalidSpawnPointId", CommandId = nil, Monster = nil }
	end
	if type(targetPlayerId) ~= "number"
		or targetPlayerId ~= targetPlayerId
		or math.abs(targetPlayerId) == math.huge
		or targetPlayerId % 1 ~= 0
		or targetPlayerId == 0 then
		return { Succeeded = false, Reason = "InvalidTargetPlayerId", CommandId = nil, Monster = nil }
	end
	if not isFiniteVector3(entryPoint) then
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
	return responseOrError
end
