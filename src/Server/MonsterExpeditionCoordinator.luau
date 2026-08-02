local CityDefenseCoordinator = require(script.Parent.CityDefenseCoordinator)
local HouseAttackCommitter = require(script.Parent.HouseAttackCommitter)
local HouseAttackTargetAccess = require(script.Parent.HouseAttackTargetAccess)
local MonsterAttackCoordinator = require(script.Parent.MonsterAttackCoordinator)
local MonsterCombatCoordinator = require(script.Parent.MonsterCombatCoordinator)
local MonsterDamageCoordinator = require(script.Parent.MonsterDamageCoordinator)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)

local MonsterExpeditionCoordinator = {}

export type ExecuteOptions = {
	HouseAccess: HouseAttackTargetAccess.Access,
	ModelAnimationConfig: MonsterAttackCoordinator.ModelAnimationConfig,
	MonsterAttackConfig: MonsterAttackCoordinator.MonsterAttackConfig,
	MoveSpeed: number,
	TurnDuration: number,
	RewardAmount: number,
	Defense: CityDefenseCoordinator.SessionOptions,
	ResolveCombatConfig: (Player, string) -> MonsterCombatCoordinator.CombatConfig?,
	CombatFirstStrike: "Attacker" | "Defender",
	SetCombatantMoving: ((Model, boolean) -> ())?,
	IsCancelled: (() -> boolean)?,
	OnDefeated: (Player, string, MonsterDamageCoordinator.DamageSource) -> (),
	OnHouseDestroyed: ((string, HouseAttackCommitter.CommitResult) -> ())?,
	OnReturnRequired: (Player, string, string) -> { Succeeded: boolean, Reason: string? },
}

export type ExpeditionResult = {
	Succeeded: boolean,
	EndReason: "Completed" | "Defeated" | "Cancelled" | "Failed",
	Reason: string?,
	DestroyedHouseIds: { string },
	RewardGranted: number,
	DefeatedDefenderMonsterIds: { string },
	AttackerDefeated: boolean,
	TowerHitCount: number,
	TowerDamageTaken: number,
}

local function updatePhase(player: Player, spawnPointId: string, phase: string)
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not record or record.State == phase then
		return
	end
	local result = MonsterRosterCoordinator.Transition(player, spawnPointId, phase)
	if not result.Succeeded then
		error(result.Reason or "MonsterPhaseTransitionFailed", 0)
	end
end

-- 输入：唯一进攻玩家、唯一防守玩家、进攻怪兽出生点和已验证的地盘坐标。
-- 输出：完整出征结果、摧毁房屋和奖励总额。
-- 内部算法：运行房屋攻击链路；每个移动/攻击帧轮询塔防和守城怪兽，
-- 守城怪兽出现时暂停建筑攻击并完成互殴，胜利后恢复原路线，死亡则结束并进入恢复分支。
function MonsterExpeditionCoordinator.Execute(
	attacker: Player,
	defender: Player,
	attackerSpawnPointId: string,
	entryPoint: Vector3,
	options: ExecuteOptions
): ExpeditionResult
	assert(attacker:IsA("Player") and defender:IsA("Player"), "攻守双方必须是 Player")
	assert(attacker ~= defender, "不能攻击自己的城市")
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.ResolveCombatConfig) == "function", "ResolveCombatConfig 必须是 function")
	assert(type(options.OnDefeated) == "function", "OnDefeated 必须是 function")
	assert(type(options.OnReturnRequired) == "function", "OnReturnRequired 必须是 function")

	local attackerRecord = MonsterRosterCoordinator.Get(attacker, attackerSpawnPointId)
	if not attackerRecord or not attackerRecord.Model then
		return {
			Succeeded = false,
			EndReason = "Failed",
			Reason = "AttackerUnavailable",
			DestroyedHouseIds = {},
			RewardGranted = 0,
			DefeatedDefenderMonsterIds = {},
			AttackerDefeated = false,
			TowerHitCount = 0,
			TowerDamageTaken = 0,
		}
	end

	local defeatedDefenderMonsterIds = {}
	local attackerDefeated = false
	local towerHitCount = 0
	local towerDamageTaken = 0
	local function onDefeated(
		defeatedPlayer: Player,
		defeatedSpawnPointId: string,
		source: MonsterDamageCoordinator.DamageSource
	)
		if defeatedPlayer == attacker then
			attackerDefeated = true
		elseif defeatedPlayer == defender then
			table.insert(defeatedDefenderMonsterIds, defeatedSpawnPointId)
		end
		options.OnDefeated(defeatedPlayer, defeatedSpawnPointId, source)
	end

	local defenseSession = CityDefenseCoordinator.Begin(
		defender,
		attacker,
		attackerSpawnPointId,
		{
			TowerAccess = options.Defense.TowerAccess,
			DefenderDetectionRadius = options.Defense.DefenderDetectionRadius,
			OnDefeated = onDefeated,
			OnTowerHit = function(_towerId, damageApplied)
				towerHitCount += 1
				towerDamageTaken += damageApplied
			end,
		}
	)
	local function closeDefense()
		defenseSession.Close()
	end

	local attackSucceeded, attackResultOrError = pcall(
		MonsterAttackCoordinator.Execute,
		defender,
		attackerRecord.Model,
		entryPoint,
		{
			HouseAccess = options.HouseAccess,
			ModelAnimationConfig = options.ModelAnimationConfig,
			MonsterAttackConfig = options.MonsterAttackConfig,
			MoveSpeed = options.MoveSpeed,
			TurnDuration = options.TurnDuration,
			RewardAmount = options.RewardAmount,
			RewardPlayer = attacker,
			OnHouseDestroyed = options.OnHouseDestroyed,
			OnPhaseChanged = function(phase)
				updatePhase(attacker, attackerSpawnPointId, phase)
			end,
			PollInterruption = function()
				if options.IsCancelled and options.IsCancelled() then
					return { Kind = "CommandCancelled" }
				end
				local event = defenseSession.Poll()
				return if event.Kind == "None" then nil else event
			end,
			HandleInterruption = function(event)
				if event.Kind == "CommandCancelled" then
					return { Continue = false, Reason = "Cancelled" }
				end
				if event.Kind == "AttackerDefeated" then
					return { Continue = false, Reason = "AttackerDefeated" }
				end
				if event.Kind ~= "DefenderMonster" or not event.DefenderSpawnPointId then
					return { Continue = false, Reason = "UnknownDefenseEvent" }
				end

				local attackerConfig = options.ResolveCombatConfig(attacker, attackerSpawnPointId)
				local defenderConfig = options.ResolveCombatConfig(
					defender,
					event.DefenderSpawnPointId
				)
				if not attackerConfig or not defenderConfig then
					CityDefenseCoordinator.ReleaseInterceptor(
						defender,
						event.DefenderSpawnPointId
					)
					return { Continue = false, Reason = "MissingCombatConfig" }
				end

				local attackerBeforeCombat = MonsterRosterCoordinator.Get(
					attacker,
					attackerSpawnPointId
				)
				local resumeState = if attackerBeforeCombat
					then attackerBeforeCombat.State
					else "MovingToTarget"
				local combatResult = MonsterCombatCoordinator.Execute(
					{
						Player = attacker,
						SpawnPointId = attackerSpawnPointId,
					},
					{
						Player = defender,
						SpawnPointId = event.DefenderSpawnPointId,
					},
					{
						AttackerConfig = attackerConfig,
						DefenderConfig = defenderConfig,
						ApproachingSide = "Defender",
						FirstStrike = options.CombatFirstStrike,
						AttackerResumeState = resumeState,
						DefenderResumeState = "IdleAtSpawn",
						IsCancelled = options.IsCancelled,
						OnDefeated = onDefeated,
						SetMoving = options.SetCombatantMoving,
					}
				)
				if combatResult.Succeeded and combatResult.Winner == "Attacker" then
					return { Continue = true, Reason = nil }
				end
				if combatResult.AttackerDefeated then
					return { Continue = false, Reason = "AttackerDefeated" }
				end
				return {
					Continue = false,
					Reason = combatResult.Reason or "MonsterCombatFailed",
				}
			end,
		}
	)
	closeDefense()
	if not attackSucceeded then
		error(attackResultOrError, 0)
	end
	local attackResult = attackResultOrError

	local latest = MonsterRosterCoordinator.Get(attacker, attackerSpawnPointId)
	if not latest or latest.State == "Defeated" or latest.State == "Recovering" then
		attackerDefeated = true
		return {
			Succeeded = false,
			EndReason = "Defeated",
			Reason = "AttackerDefeated",
			DestroyedHouseIds = attackResult.DestroyedHouseIds,
			RewardGranted = attackResult.RewardGranted,
			DefeatedDefenderMonsterIds = table.clone(defeatedDefenderMonsterIds),
			AttackerDefeated = attackerDefeated,
			TowerHitCount = towerHitCount,
			TowerDamageTaken = towerDamageTaken,
		}
	end

	local endReason: "Completed" | "Cancelled" | "Failed"
	if attackResult.Succeeded and attackResult.ReachedDestination then
		endReason = "Completed"
	elseif attackResult.Reason == "Cancelled" then
		endReason = "Cancelled"
	else
		endReason = "Failed"
	end
	local callbackSucceeded, returnResultOrError = pcall(
		options.OnReturnRequired,
		attacker,
		attackerSpawnPointId,
		endReason
	)
	if not callbackSucceeded then
		warn("启动怪兽回城失败：", returnResultOrError)
		endReason = "Failed"
		attackResult.Reason = "ReturnStartFailed"
	elseif type(returnResultOrError) ~= "table" or not returnResultOrError.Succeeded then
		endReason = "Failed"
		attackResult.Reason = if type(returnResultOrError) == "table"
			then returnResultOrError.Reason or "ReturnStartFailed"
			else "InvalidReturnResult"
	end

	return {
		Succeeded = endReason == "Completed",
		EndReason = endReason,
		Reason = attackResult.Reason,
		DestroyedHouseIds = attackResult.DestroyedHouseIds,
		RewardGranted = attackResult.RewardGranted,
		DefeatedDefenderMonsterIds = table.clone(defeatedDefenderMonsterIds),
		AttackerDefeated = attackerDefeated,
		TowerHitCount = towerHitCount,
		TowerDamageTaken = towerDamageTaken,
	}
end

return MonsterExpeditionCoordinator
