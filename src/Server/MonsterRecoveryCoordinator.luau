local Players = game:GetService("Players")

local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)

local MonsterRecoveryCoordinator = {}

export type BeginOptions = {
	RecoveryDuration: number,
	ResolveTemplate: (string) -> Model?,
	OnRespawned: ((Player, string, Model) -> ())?,
}

local recoveryIds: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" })

local function nextRecoveryId(player: Player, spawnPointId: string): number
	local ids = recoveryIds[player]
	if not ids then
		ids = {}
		recoveryIds[player] = ids
	end
	local id = (ids[spawnPointId] or 0) + 1
	ids[spawnPointId] = id
	return id
end

local function isCurrent(player: Player, spawnPointId: string, recoveryId: number): boolean
	local ids = recoveryIds[player]
	return ids ~= nil and ids[spawnPointId] == recoveryId
end

-- 输入：已死亡怪兽的玩家、出生点和恢复配置。
-- 输出：是否接受恢复、恢复完成时间。
-- 内部算法：Defeated -> Recovering，延时后按出生点当前 MonsterKey 重新生成。
function MonsterRecoveryCoordinator.Begin(
	player: Player,
	spawnPointId: string,
	options: BeginOptions
)
	assert(type(options) == "table", "options 必须是 table")
	assert(
		type(options.RecoveryDuration) == "number" and options.RecoveryDuration >= 0,
		"RecoveryDuration 必须大于等于 0"
	)
	assert(type(options.ResolveTemplate) == "function", "ResolveTemplate 必须是 function")

	local current = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not current then
		return {
			Succeeded = false,
			Reason = "UnknownSpawnPoint",
			RespawnAt = nil,
		}
	end
	if current.State ~= "Defeated" then
		return {
			Succeeded = false,
			Reason = "MonsterNotDefeated",
			RespawnAt = current.RespawnAt,
		}
	end

	local transition = MonsterRosterCoordinator.Transition(player, spawnPointId, "Recovering")
	if not transition.Succeeded then
		return {
			Succeeded = false,
			Reason = transition.Reason,
			RespawnAt = nil,
		}
	end

	local respawnAt = workspace:GetServerTimeNow() + options.RecoveryDuration
	MonsterRosterCoordinator.SetRespawnAt(player, spawnPointId, respawnAt)
	local recoveryId = nextRecoveryId(player, spawnPointId)

	task.delay(options.RecoveryDuration, function()
		if not isCurrent(player, spawnPointId, recoveryId) then
			return
		end
		if player.Parent ~= Players then
			return
		end
		local latest = MonsterRosterCoordinator.Get(player, spawnPointId)
		if not latest or latest.State ~= "Recovering" then
			return
		end

		local template = options.ResolveTemplate(latest.MonsterKey)
		if not template or not template:IsA("Model") then
			warn("恢复怪兽失败，找不到模板：", latest.MonsterKey)
			return
		end
		local result = MonsterRosterCoordinator.Respawn(player, spawnPointId, template)
		if not result.Succeeded then
			warn("恢复怪兽失败：", result.Reason)
			return
		end
		if options.OnRespawned and result.Record and result.Record.Model then
			local succeeded, callbackError = pcall(
				options.OnRespawned,
				player,
				spawnPointId,
				result.Record.Model
			)
			if not succeeded then
				warn("怪兽恢复回调失败：", callbackError)
			end
		end
	end)

	return {
		Succeeded = true,
		Reason = nil,
		RespawnAt = respawnAt,
	}
end

return MonsterRecoveryCoordinator
