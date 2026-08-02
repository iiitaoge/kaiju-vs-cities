local Players = game:GetService("Players")

local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)

local MonsterReturnCoordinator = {}

export type ReturnResult = {
	Succeeded: boolean,
	Reason: string?,
}

export type BeginOptions = {
	-- 以后可注入“走回去”或“隐藏后回到出生点”，但必须让同一模型最终位于 SpawnCFrame。
	ExecuteReturn: (Model, CFrame) -> ReturnResult,
	OnReturned: ((Player, string, Model) -> ())?,
}

local returnIds: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" })

local function nextReturnId(player: Player, spawnPointId: string): number
	local ids = returnIds[player]
	if not ids then
		ids = {}
		returnIds[player] = ids
	end
	local id = (ids[spawnPointId] or 0) + 1
	ids[spawnPointId] = id
	return id
end

-- 输入：存活且已经结束攻击的怪兽，以及显式回城算法。
-- 输出：是否接受回城任务；实际完成通过状态和 OnReturned 体现。
-- 内部算法：切换 Returning，异步执行注入策略，确认模型仍存活后切回 IdleAtSpawn。
function MonsterReturnCoordinator.Begin(
	player: Player,
	spawnPointId: string,
	options: BeginOptions
): ReturnResult
	assert(type(options) == "table" and type(options.ExecuteReturn) == "function", "ExecuteReturn 必须是 function")
	local current = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not current or not current.Model then
		return { Succeeded = false, Reason = "MonsterUnavailable" }
	end
	local transition = MonsterRosterCoordinator.Transition(player, spawnPointId, "Returning")
	if not transition.Succeeded then
		return { Succeeded = false, Reason = transition.Reason }
	end

	local returnId = nextReturnId(player, spawnPointId)
	task.spawn(function()
		if player.Parent ~= Players then
			return
		end
		local latest = MonsterRosterCoordinator.Get(player, spawnPointId)
		if not latest or not latest.Model then
			return
		end
		local succeeded, resultOrError = pcall(
			options.ExecuteReturn,
			latest.Model,
			latest.SpawnCFrame
		)
		if not succeeded then
			warn("怪兽回城算法失败：", resultOrError)
			return
		end
		local ids = returnIds[player]
		if not ids or ids[spawnPointId] ~= returnId then
			return
		end
		if not resultOrError.Succeeded then
			warn("怪兽回城失败：", resultOrError.Reason)
			return
		end

		latest = MonsterRosterCoordinator.Get(player, spawnPointId)
		if not latest or not latest.Model or latest.State ~= "Returning" then
			return
		end
		local completed = MonsterRosterCoordinator.Transition(
			player,
			spawnPointId,
			"IdleAtSpawn"
		)
		if completed.Succeeded and options.OnReturned and completed.Record and completed.Record.Model then
			local callbackSucceeded, callbackError = pcall(
				options.OnReturned,
				player,
				spawnPointId,
				completed.Record.Model
			)
			if not callbackSucceeded then
				warn("怪兽回城回调失败：", callbackError)
			end
		end
	end)

	return { Succeeded = true, Reason = nil }
end

return MonsterReturnCoordinator
