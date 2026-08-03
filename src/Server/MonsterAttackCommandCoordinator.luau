local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local PlayerTerritoryAccess = require(script.Parent.PlayerTerritoryAccess)
local MonsterStateRules = require(ReplicatedStorage.Shared.Monster.MonsterStateRules)
local TerritoryPointRules = require(ReplicatedStorage.Shared.Monster.TerritoryPointRules)

local MonsterAttackCommandCoordinator = {}

export type CommandResult = {
	Succeeded: boolean,
	Reason: string?,
	CommandId: number?,
	Monster: Model?,
}

export type CommandContext = {
	CommandId: number,
	Attacker: Player,
	Defender: Player,
	AttackerSpawnPointId: string,
	EntryPoint: Vector3,
	StartedAt: number,
}

export type ExecuteOptions = {
	TerritoryAccess: PlayerTerritoryAccess.Access,
	-- 必须立即开始异步之外的完整远征；本回调自身运行在新 task 中。
	StartExpedition: (CommandContext, () -> boolean) -> any,
	OnCommandFinished: (CommandContext, boolean, any) -> (),
}

local commandIds: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" })
local activeCommandIds: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" })

local function nextCommandId(player: Player, spawnPointId: string): number
	local ids = commandIds[player]
	if not ids then
		ids = {}
		commandIds[player] = ids
	end
	local id = (ids[spawnPointId] or 0) + 1
	ids[spawnPointId] = id
	return id
end

local function currentCommandId(player: Player, spawnPointId: string): number?
	local ids = commandIds[player]
	return if ids then ids[spawnPointId] else nil
end

local function setActiveCommand(player: Player, spawnPointId: string, commandId: number?)
	local ids = activeCommandIds[player]
	if not ids and commandId ~= nil then
		ids = {}
		activeCommandIds[player] = ids
	end
	if ids then
		ids[spawnPointId] = commandId
	end
end

local function activeCommandId(player: Player, spawnPointId: string): number?
	local ids = activeCommandIds[player]
	return if ids then ids[spawnPointId] else nil
end

-- 输入：进攻玩家、自己的出生点 ID、目标玩家和目标地盘内坐标。
-- 输出：立即返回是否接受命令、命令 ID 和可跟随模型。
-- 内部算法：验证怪兽归属/空闲、目标在线、地盘与坐标，再异步启动远征。
function MonsterAttackCommandCoordinator.Execute(
	attacker: Player,
	attackerSpawnPointId: string,
	targetPlayer: Player,
	entryPoint: Vector3,
	options: ExecuteOptions
): CommandResult
	if typeof(attacker) ~= "Instance" or not attacker:IsA("Player") then
		return { Succeeded = false, Reason = "InvalidAttacker", CommandId = nil, Monster = nil }
	end
	if attacker.Parent ~= Players then
		return { Succeeded = false, Reason = "AttackerUnavailable", CommandId = nil, Monster = nil }
	end
	if type(attackerSpawnPointId) ~= "string" or attackerSpawnPointId == "" then
		return { Succeeded = false, Reason = "InvalidMonsterId", CommandId = nil, Monster = nil }
	end
	if typeof(targetPlayer) ~= "Instance"
		or not targetPlayer:IsA("Player")
		or targetPlayer.Parent ~= Players then
		return { Succeeded = false, Reason = "TargetPlayerUnavailable", CommandId = nil, Monster = nil }
	end
	if targetPlayer == attacker then
		return { Succeeded = false, Reason = "CannotAttackSelf", CommandId = nil, Monster = nil }
	end
	if type(options) ~= "table"
		or type(options.TerritoryAccess) ~= "table"
		or type(options.TerritoryAccess.ListUnlockedTerritories) ~= "function"
		or type(options.StartExpedition) ~= "function"
		or type(options.OnCommandFinished) ~= "function" then
		return { Succeeded = false, Reason = "InvalidCommandOptions", CommandId = nil, Monster = nil }
	end

	local monster = MonsterRosterCoordinator.Get(attacker, attackerSpawnPointId)
	if not monster or not monster.Model then
		return { Succeeded = false, Reason = "MonsterUnavailable", CommandId = nil, Monster = nil }
	end
	local permission = MonsterStateRules.CheckAttack(monster.State)
	if not permission.Allowed then
		return { Succeeded = false, Reason = permission.Reason, CommandId = nil, Monster = monster.Model }
	end

	local territories = options.TerritoryAccess.ListUnlockedTerritories(targetPlayer)
	if #territories == 0 then
		return { Succeeded = false, Reason = "TargetTerritoryUnavailable", CommandId = nil, Monster = monster.Model }
	end

	local validTerritoryCount = 0
	local allowed = false
	for _, territory in territories do
		local pointCheck = TerritoryPointRules.Check(
			territory.CFrame,
			territory.Size,
			entryPoint
		)
		if pointCheck.Reason == "InvalidEntryPoint" then
			return { Succeeded = false, Reason = pointCheck.Reason, CommandId = nil, Monster = monster.Model }
		end
		if pointCheck.Reason ~= "InvalidTerritory" then
			validTerritoryCount += 1
		end
		if pointCheck.Allowed then
			allowed = true
			break
		end
	end
	if not allowed then
		local reason = if validTerritoryCount > 0
			then "EntryPointOutsideTerritory"
			else "TargetTerritoryUnavailable"
		return { Succeeded = false, Reason = reason, CommandId = nil, Monster = monster.Model }
	end

	local transition = MonsterRosterCoordinator.Transition(
		attacker,
		attackerSpawnPointId,
		"Releasing"
	)
	if not transition.Succeeded then
		return { Succeeded = false, Reason = transition.Reason, CommandId = nil, Monster = monster.Model }
	end

	local commandId = nextCommandId(attacker, attackerSpawnPointId)
	local commandContext = table.freeze({
		CommandId = commandId,
		Attacker = attacker,
		Defender = targetPlayer,
		AttackerSpawnPointId = attackerSpawnPointId,
		EntryPoint = entryPoint,
		StartedAt = workspace:GetServerTimeNow(),
	})
	setActiveCommand(attacker, attackerSpawnPointId, commandId)
	local function isCancelled(): boolean
		return currentCommandId(attacker, attackerSpawnPointId) ~= commandId
			or attacker.Parent ~= Players
			or targetPlayer.Parent ~= Players
	end

	task.spawn(function()
		local succeeded, resultOrError = pcall(
			options.StartExpedition,
			commandContext,
			isCancelled
		)
		if not succeeded then
			warn("怪兽远征执行失败：", resultOrError)
		end
		if activeCommandId(attacker, attackerSpawnPointId) == commandId then
			setActiveCommand(attacker, attackerSpawnPointId, nil)
		end
		local callbackSucceeded, callbackError = pcall(
			options.OnCommandFinished,
			commandContext,
			succeeded,
			resultOrError
		)
		if not callbackSucceeded then
			warn("怪兽命令完成回调失败：", callbackError)
		end
	end)

	return {
		Succeeded = true,
		Reason = nil,
		CommandId = commandId,
		Monster = monster.Model,
	}
end

-- 输入：玩家和自己的怪兽出生点 ID。
-- 输出：是否存在一条可取消的当前命令。
-- 内部算法：递增命令 ID；正在执行的远征会通过 IsCancelled 自行结束并进入回城。
function MonsterAttackCommandCoordinator.Cancel(player: Player, spawnPointId: string): boolean
	if activeCommandId(player, spawnPointId) == nil then
		return false
	end
	nextCommandId(player, spawnPointId)
	setActiveCommand(player, spawnPointId, nil)
	return true
end

return MonsterAttackCommandCoordinator
