local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DefenseTowerAccess = require(script.Parent.DefenseTowerAccess)
local MonsterDamageCoordinator = require(script.Parent.MonsterDamageCoordinator)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local EnemyTargetSelector = require(ReplicatedStorage.Shared.Monster.EnemyTargetSelector)

local CityDefenseCoordinator = {}

export type SessionOptions = {
	TowerAccess: DefenseTowerAccess.Access,
	DefenderDetectionRadius: number,
	OnDefeated: ((Player, string, MonsterDamageCoordinator.DamageSource) -> ())?,
	OnTowerHit: ((string, number) -> ())?,
}

export type DefenseEvent = {
	Kind: "None" | "AttackerDefeated" | "DefenderMonster",
	DefenderSpawnPointId: string?,
}

export type Session = {
	Poll: () -> DefenseEvent,
	Close: () -> (),
}

local function horizontalDistance(a: Vector3, b: Vector3): number
	return (Vector2.new(a.X, a.Z) - Vector2.new(b.X, b.Z)).Magnitude
end

-- 输入：唯一防守玩家、唯一进攻怪兽和防御访问接口。
-- 输出：可轮询的防御会话；塔防在独立循环持续结算，Poll 最多预约一只守城怪兽。
-- 内部算法：防御塔独立按冷却攻击；空闲守城怪兽按距离和稳定 ID 选择并切换为 Defending。
function CityDefenseCoordinator.Begin(
	defender: Player,
	attacker: Player,
	attackerSpawnPointId: string,
	options: SessionOptions
): Session
	assert(defender:IsA("Player") and attacker:IsA("Player"), "攻守双方必须是 Player")
	assert(defender ~= attacker, "防守玩家不能是进攻玩家")
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.TowerAccess) == "table", "TowerAccess 必须是 table")
	assert(type(options.TowerAccess.ListAliveTowers) == "function", "ListAliveTowers 必须是 function")
	assert(
		type(options.DefenderDetectionRadius) == "number"
			and options.DefenderDetectionRadius >= 0,
		"DefenderDetectionRadius 无效"
	)
	assert(options.OnTowerHit == nil or type(options.OnTowerHit) == "function", "OnTowerHit 无效")

	local closed = false
	local attackerDefeated = false
	local towerNextAttackAt: { [string]: number } = {}

	local function applyTowerDamage()
		local attackerRecord = MonsterRosterCoordinator.Get(attacker, attackerSpawnPointId)
		if not attackerRecord
			or not attackerRecord.Model
			or attackerRecord.State == "Defeated"
			or attackerRecord.State == "Recovering" then
			attackerDefeated = true
			return
		end

		local attackerPosition = attackerRecord.Model:GetPivot().Position
		local now = workspace:GetServerTimeNow()
		for _, tower in options.TowerAccess.ListAliveTowers(defender) do
			if type(tower.TowerId) ~= "string"
				or typeof(tower.Position) ~= "Vector3"
				or type(tower.Range) ~= "number"
				or tower.Range < 0
				or type(tower.Damage) ~= "number"
				or tower.Damage <= 0
				or type(tower.AttackInterval) ~= "number"
				or tower.AttackInterval <= 0 then
				continue
			end
			if not tower.Active or now < (towerNextAttackAt[tower.TowerId] or 0) then
				continue
			end
			if horizontalDistance(tower.Position, attackerPosition) > tower.Range then
				continue
			end

			towerNextAttackAt[tower.TowerId] = now + tower.AttackInterval
			local damageResult = MonsterDamageCoordinator.ApplyDamage(
				attacker,
				attackerSpawnPointId,
				{
					OwnerUserId = defender.UserId,
					SourceId = tower.TowerId,
					Kind = "DefenseTower",
				},
				tower.Damage,
				{ OnDefeated = options.OnDefeated }
			)
			if damageResult.Succeeded
				and damageResult.DamageApplied > 0
				and options.OnTowerHit then
				local callbackSucceeded, callbackError = pcall(
					options.OnTowerHit,
					tower.TowerId,
					damageResult.DamageApplied
				)
				if not callbackSucceeded then
					warn("防御塔命中回调失败：", callbackError)
				end
			end
			if damageResult.Defeated then
				attackerDefeated = true
				return
			end
		end
	end

	task.spawn(function()
		while not closed and not attackerDefeated do
			applyTowerDamage()
			if not closed and not attackerDefeated then
				task.wait(0.1)
			end
		end
	end)

	local function poll(): DefenseEvent
		if closed then
			return { Kind = "None", DefenderSpawnPointId = nil }
		end
		if attackerDefeated then
			return { Kind = "AttackerDefeated", DefenderSpawnPointId = nil }
		end
		local attackerRecord = MonsterRosterCoordinator.Get(attacker, attackerSpawnPointId)
		if not attackerRecord or not attackerRecord.Model then
			attackerDefeated = true
			return { Kind = "AttackerDefeated", DefenderSpawnPointId = nil }
		end
		local attackerPosition = attackerRecord.Model:GetPivot().Position

		local candidates = {}
		for _, record in MonsterRosterCoordinator.List(defender) do
			if record.State == "IdleAtSpawn" and record.Model then
				table.insert(candidates, {
					TargetId = record.SpawnPointId,
					OwnerUserId = defender.UserId,
					Position = record.Model:GetPivot().Position,
					Active = true,
				})
			end
		end
		local selected = EnemyTargetSelector.Select(attackerPosition, candidates, {
			TargetOwnerUserId = defender.UserId,
			MaxDistance = options.DefenderDetectionRadius,
		})
		if not selected then
			return { Kind = "None", DefenderSpawnPointId = nil }
		end

		local reserved = MonsterRosterCoordinator.Transition(
			defender,
			selected.TargetId,
			"Defending"
		)
		if not reserved.Succeeded then
			return { Kind = "None", DefenderSpawnPointId = nil }
		end
		return {
			Kind = "DefenderMonster",
			DefenderSpawnPointId = selected.TargetId,
		}
	end

	return {
		Poll = poll,
		Close = function()
			closed = true
		end,
	}
end

function CityDefenseCoordinator.ReleaseInterceptor(defender: Player, spawnPointId: string): boolean
	local record = MonsterRosterCoordinator.Get(defender, spawnPointId)
	if not record or record.State ~= "Defending" then
		return false
	end
	return MonsterRosterCoordinator.Transition(
		defender,
		spawnPointId,
		"IdleAtSpawn"
	).Succeeded
end

return CityDefenseCoordinator
