--[[
	职责：接受并跟踪一只怪兽的服务器权威单人空地出征命令。
	输入：在线玩家、自己的 SpawnPointId、落点，以及范围访问和执行回调。
	输出：立即返回命令是否接受、CommandId 和怪兽 Model。
	内部算法：提交瞬间确认没有其他玩家，校验权威 Bounds、怪兽空闲状态，
		切换 Releasing 后异步执行；命令接受后新玩家加入不会取消当前出征。
	不负责：罐体动画、怪兽移动、攻击动画、奖励或客户端 UI。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugLog = require(ReplicatedStorage.Shared.DebugLog)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterStateRules = require(ReplicatedStorage.Shared.Monster.MonsterStateRules)
local TerritoryPointRules = require(ReplicatedStorage.Shared.Monster.TerritoryPointRules)

local attackCoordinateLog = DebugLog.Create("AttackSelectionCoordinates")

local SoloMonsterAttackCommandCoordinator = {}

export type Area = {
	CFrame: CFrame,
	Size: Vector3,
}

export type AreaAccess = {
	Resolve: () -> (Area?, string?),
}

export type CommandContext = {
	CommandId: number,
	Player: Player,
	SpawnPointId: string,
	EntryPoint: Vector3,
	StartedAt: number,
}

export type ExecuteOptions = {
	AreaAccess: AreaAccess,
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

local function hasOtherPlayer(player: Player): boolean
	for _, candidate in Players:GetPlayers() do
		if candidate ~= player then
			return true
		end
	end
	return false
end

function SoloMonsterAttackCommandCoordinator.Execute(
	player: Player,
	spawnPointId: string,
	entryPoint: Vector3,
	options: ExecuteOptions
)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return { Succeeded = false, Reason = "InvalidPlayer", CommandId = nil, Monster = nil }
	end
	if player.Parent ~= Players then
		return { Succeeded = false, Reason = "PlayerUnavailable", CommandId = nil, Monster = nil }
	end
	if type(spawnPointId) ~= "string" or spawnPointId == "" then
		return { Succeeded = false, Reason = "InvalidMonsterId", CommandId = nil, Monster = nil }
	end
	if type(options) ~= "table"
		or type(options.AreaAccess) ~= "table"
		or type(options.AreaAccess.Resolve) ~= "function"
		or type(options.StartExpedition) ~= "function"
		or type(options.OnCommandFinished) ~= "function" then
		return { Succeeded = false, Reason = "InvalidCommandOptions", CommandId = nil, Monster = nil }
	end
	if hasOtherPlayer(player) then
		return { Succeeded = false, Reason = "SoloAttackUnavailable", CommandId = nil, Monster = nil }
	end

	local monster = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not monster or not monster.Model then
		return { Succeeded = false, Reason = "MonsterUnavailable", CommandId = nil, Monster = nil }
	end
	local permission = MonsterStateRules.CheckAttack(monster.State)
	if not permission.Allowed then
		return { Succeeded = false, Reason = permission.Reason, CommandId = nil, Monster = monster.Model }
	end

	local area, areaReason = options.AreaAccess.Resolve()
	if not area then
		return {
			Succeeded = false,
			Reason = areaReason or "SoloAttackBoundsUnavailable",
			CommandId = nil,
			Monster = monster.Model,
		}
	end
	local pointCheck = TerritoryPointRules.Check(area.CFrame, area.Size, entryPoint)
	if not pointCheck.Allowed then
		attackCoordinateLog(
			"[SERVER_TERRITORY]",
			"mode=Solo",
			string.format("player=%s:%d", player.Name, player.UserId),
			"allowed=false",
			"reason=" .. tostring(pointCheck.Reason)
		)
		return {
			Succeeded = false,
			Reason = pointCheck.Reason or "EntryPointOutsideTerritory",
			CommandId = nil,
			Monster = monster.Model,
		}
	end
	attackCoordinateLog(
		"[SERVER_TERRITORY]",
		"mode=Solo",
		string.format("player=%s:%d", player.Name, player.UserId),
		"allowed=true",
		"bounds=SoloAttackBounds"
	)

	local transition = MonsterRosterCoordinator.Transition(player, spawnPointId, "Releasing")
	if not transition.Succeeded then
		return { Succeeded = false, Reason = transition.Reason, CommandId = nil, Monster = monster.Model }
	end

	local commandId = nextCommandId(player, spawnPointId)
	local context = table.freeze({
		CommandId = commandId,
		Player = player,
		SpawnPointId = spawnPointId,
		EntryPoint = entryPoint,
		StartedAt = workspace:GetServerTimeNow(),
	})
	setActiveCommand(player, spawnPointId, commandId)
	local function isCancelled(): boolean
		return currentCommandId(player, spawnPointId) ~= commandId
			or player.Parent ~= Players
	end

	task.spawn(function()
		local succeeded, resultOrError = pcall(
			options.StartExpedition,
			context,
			isCancelled
		)
		local active = activeCommandIds[player]
		if active and active[spawnPointId] == commandId then
			setActiveCommand(player, spawnPointId, nil)
		end
		local callbackSucceeded, callbackError = pcall(
			options.OnCommandFinished,
			context,
			succeeded,
			resultOrError
		)
		if not callbackSucceeded then
			warn("单人出征完成回调失败：", callbackError)
		end
	end)

	return {
		Succeeded = true,
		Reason = nil,
		CommandId = commandId,
		Monster = monster.Model,
	}
end

return SoloMonsterAttackCommandCoordinator
