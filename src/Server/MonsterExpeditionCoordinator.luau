local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CityDefenseCoordinator = require(script.Parent.CityDefenseCoordinator)
local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local GodzillaService = require(script.Parent.GodzillaService)
local HouseAttackCommitter = require(script.Parent.HouseAttackCommitter)
local HouseAttackTargetAccess = require(script.Parent.HouseAttackTargetAccess)
local MonsterAttackCoordinator = require(script.Parent.MonsterAttackCoordinator)
local MonsterCombatCoordinator = require(script.Parent.MonsterCombatCoordinator)
local MonsterDamageCoordinator = require(script.Parent.MonsterDamageCoordinator)
local MonsterCombatDiagnosticLog = require(script.Parent.MonsterCombatDiagnosticLog)
local MonsterExpeditionAttackPhaseCoordinator = require(
	script.Parent.MonsterExpeditionAttackPhaseCoordinator
)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)

local MonsterExpeditionCoordinator = {}

export type ExecuteOptions = {
	TraceId: string,
	TargetRegionId: string,
	HouseAccess: HouseAttackTargetAccess.Access,
	ModelAnimationConfig: MonsterAttackCoordinator.ModelAnimationConfig,
	MonsterAttackConfig: MonsterAttackCoordinator.MonsterAttackConfig,
	MoveSpeed: number,
	MaxTravelDuration: number?,
	TimingSafetyMargin: number?,
	TurnDuration: number,
	WalkAnimation: any?,
	RewardAmount: number,
	MaxExpeditionDuration: number,
	DuelResolutionDuration: number,
	DuelWatchdogDuration: number,
	Defense: CityDefenseCoordinator.SessionOptions,
	ResolveCombatConfig: (Player, string) -> MonsterCombatCoordinator.CombatConfig?,
	CombatFirstStrike: "Attacker" | "Defender",
	SetCombatantMoving: ((Model, boolean, number?) -> ())?,
	IsCancelled: (() -> boolean)?,
	OnDefeated: (Player, string, MonsterDamageCoordinator.DamageSource) -> (),
	OnHouseDestroyed: ((string, HouseAttackCommitter.CommitResult) -> ())?,
	OnReturnRequired: (Player, string, string) -> { Succeeded: boolean, Reason: string? },
	OnDefenderReturnRequired: (Player, string) -> { Succeeded: boolean, Reason: string? },
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

-- 输入：唯一进攻玩家、唯一防守玩家、进攻怪兽出生点、已验证落点和目标区域。
-- 输出：完整出征结果、摧毁房屋和奖励总额。
-- 内部算法：先移动到落点，再逐只清空目标区域守卫；随后固定在落点持续发射激光，
-- 发射中转向并按距离逐栋消耗一次建筑伤害预算，最后一栋允许残血。
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
	assert(type(options.TraceId) == "string" and options.TraceId ~= "", "TraceId 无效")
	assert(
		type(options.TargetRegionId) == "string" and options.TargetRegionId ~= "",
		"TargetRegionId 无效"
	)
	assert(type(options.ResolveCombatConfig) == "function", "ResolveCombatConfig 必须是 function")
	assert(type(options.OnDefeated) == "function", "OnDefeated 必须是 function")
	assert(type(options.OnReturnRequired) == "function", "OnReturnRequired 必须是 function")
	assert(type(options.OnDefenderReturnRequired) == "function", "OnDefenderReturnRequired 必须是 function")
	assert(type(options.MaxExpeditionDuration) == "number" and options.MaxExpeditionDuration > 0, "MaxExpeditionDuration 无效")

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

	local expeditionActive = true
	local expeditionExpired = false
	local activeDefenderSpawnPointId: string? = nil
	local lastCombatResult = nil
	local function emitTerminal(attackResult, latest, terminalPath: "Recovery" | "Return", endReason: string)
		MonsterCombatDiagnosticLog.Emit("EXPEDITION_TERMINAL", {
			TraceId = options.TraceId,
			AttackResultReason = attackResult.Reason or "None",
			CombatResultReason = if lastCombatResult
				then lastCombatResult.Reason
				else "None",
			CombatSucceeded = if lastCombatResult
				then lastCombatResult.Succeeded
				else false,
			CombatWinner = if lastCombatResult
				then lastCombatResult.Winner
				else "None",
			EndReason = endReason,
			AttackerState = if latest then latest.State else "None",
			AttackerHealth = if latest then latest.Health else 0,
			AttackerModelExists = latest ~= nil and latest.Model ~= nil,
			TerminalPath = terminalPath,
		})
	end
	local function cancelCombatant(player: Player, spawnPointId: string)
		local record = MonsterRosterCoordinator.Get(player, spawnPointId)
		if record and record.Model then
			GodzillaMoveService.Cancel(record.Model)
			GodzillaService.StopMoving(record.Model)
		end
	end
	local function cancelActiveMotion()
		cancelCombatant(attacker, attackerSpawnPointId)
		if activeDefenderSpawnPointId then
			cancelCombatant(defender, activeDefenderSpawnPointId)
		end
	end
	task.delay(options.MaxExpeditionDuration, function()
		if expeditionActive then
			expeditionExpired = true
			cancelActiveMotion()
		end
	end)
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
			TraceId = options.TraceId,
			TargetRegionId = options.TargetRegionId,
			TowerAccess = options.Defense.TowerAccess,
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
		MonsterExpeditionAttackPhaseCoordinator.Execute,
		defender,
		attackerRecord.Model,
		entryPoint,
		{
			TargetRegionId = options.TargetRegionId,
			HouseAccess = options.HouseAccess,
			ModelAnimationConfig = options.ModelAnimationConfig,
			MonsterAttackConfig = options.MonsterAttackConfig,
			MoveSpeed = options.MoveSpeed,
			MaxTravelDuration = options.MaxTravelDuration,
			TimingSafetyMargin = options.TimingSafetyMargin,
			TurnDuration = options.TurnDuration,
			WalkAnimation = options.WalkAnimation,
			RewardAmount = options.RewardAmount,
			RewardPlayer = attacker,
			PollStopReason = function()
				if options.IsCancelled and options.IsCancelled() then
					return "Cancelled"
				end
				if expeditionExpired then
					return "ExpeditionTimedOut"
				end
				local latest = MonsterRosterCoordinator.Get(attacker, attackerSpawnPointId)
				if not latest
					or not latest.Model
					or latest.State == "Defeated"
					or latest.State == "Recovering"
				then
					return "AttackerDefeated"
				end
				return nil
			end,
			OnHouseDestroyed = options.OnHouseDestroyed,
			OnPhaseChanged = function(phase)
				updatePhase(attacker, attackerSpawnPointId, phase)
			end,
			PollInterruption = function()
				if options.IsCancelled and options.IsCancelled() then
					return { Kind = "CommandCancelled" }
				end
				if expeditionExpired then
					return { Kind = "ExpeditionTimedOut" }
				end
				local event = defenseSession.Poll()
				return if event.Kind == "None" then nil else event
			end,
			HandleInterruption = function(event)
				if event.Kind == "CommandCancelled" then
					return { Continue = false, Reason = "Cancelled" }
				end
				if event.Kind == "ExpeditionTimedOut" then
					return { Continue = false, Reason = "ExpeditionTimedOut" }
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
				local defenderBeforeCombat = MonsterRosterCoordinator.Get(
					defender,
					event.DefenderSpawnPointId
				)
				local attackerDefinition = if attackerBeforeCombat
					then MonsterCatalog.Get(attackerBeforeCombat.MonsterKey)
					else nil
				local defenderDefinition = if defenderBeforeCombat
					then MonsterCatalog.Get(defenderBeforeCombat.MonsterKey)
					else nil
				MonsterCombatDiagnosticLog.Emit("DUEL_MATCHED", {
					TraceId = options.TraceId,
					AttackerUserId = attacker.UserId,
					AttackerSpawnPointId = attackerSpawnPointId,
					AttackerState = if attackerBeforeCombat then attackerBeforeCombat.State else "None",
					AttackerMonsterKey = if attackerBeforeCombat then attackerBeforeCombat.MonsterKey else "None",
					AttackerCatalogLevel = if attackerDefinition then attackerDefinition.Level else 0,
					AttackerHealth = if attackerBeforeCombat then attackerBeforeCombat.Health else 0,
					AttackerMaxHealth = if attackerBeforeCombat then attackerBeforeCombat.MaxHealth else 0,
					AttackerModelMonsterKey = if attackerBeforeCombat and attackerBeforeCombat.Model
						then tostring(attackerBeforeCombat.Model:GetAttribute("MonsterKey"))
						else "None",
					AttackerModelScale = if attackerBeforeCombat and attackerBeforeCombat.Model
						then attackerBeforeCombat.Model:GetAttribute("MonsterModelScale") or 0
						else 0,
					DefenderUserId = defender.UserId,
					DefenderSpawnPointId = event.DefenderSpawnPointId,
					DefenderState = if defenderBeforeCombat then defenderBeforeCombat.State else "None",
					DefenderMonsterKey = if defenderBeforeCombat then defenderBeforeCombat.MonsterKey else "None",
					DefenderCatalogLevel = if defenderDefinition then defenderDefinition.Level else 0,
					DefenderHealth = if defenderBeforeCombat then defenderBeforeCombat.Health else 0,
					DefenderMaxHealth = if defenderBeforeCombat then defenderBeforeCombat.MaxHealth else 0,
					DefenderModelMonsterKey = if defenderBeforeCombat and defenderBeforeCombat.Model
						then tostring(defenderBeforeCombat.Model:GetAttribute("MonsterKey"))
						else "None",
					DefenderModelScale = if defenderBeforeCombat and defenderBeforeCombat.Model
						then defenderBeforeCombat.Model:GetAttribute("MonsterModelScale") or 0
						else 0,
					AttackerDamage = attackerConfig.Damage,
					DefenderDamage = defenderConfig.Damage,
					AttackerAttackInterval = attackerConfig.AttackInterval,
					DefenderAttackInterval = defenderConfig.AttackInterval,
				})
				local resumeState = if attackerBeforeCombat
					then attackerBeforeCombat.State
					else "MovingToTarget"
				activeDefenderSpawnPointId = event.DefenderSpawnPointId
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
						TraceId = options.TraceId,
						AttackerConfig = attackerConfig,
						DefenderConfig = defenderConfig,
						ApproachingSide = "Defender",
						FirstStrike = options.CombatFirstStrike,
						AttackerResumeState = resumeState,
						DefenderResumeState = "Defending",
						IsCancelled = function()
							return expeditionExpired
								or (options.IsCancelled and options.IsCancelled())
								or false
						end,
						OnDefeated = onDefeated,
						SetMoving = options.SetCombatantMoving,
						ResolutionDuration = options.DuelResolutionDuration,
						WatchdogDuration = options.DuelWatchdogDuration,
					}
				)
				lastCombatResult = {
					Succeeded = combatResult.Succeeded,
					Reason = combatResult.Reason or "None",
					Winner = combatResult.Winner or "None",
				}
				activeDefenderSpawnPointId = nil
				local defenderAfterCombat = MonsterRosterCoordinator.Get(
					defender,
					event.DefenderSpawnPointId
				)
				if defenderAfterCombat
					and defenderAfterCombat.Model
					and defenderAfterCombat.State == "Defending"
				then
					local returned = options.OnDefenderReturnRequired(
						defender,
						event.DefenderSpawnPointId
					)
					if not returned.Succeeded then
						warn("启动防守怪兽回位失败：", returned.Reason)
					end
				end
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
	expeditionActive = false
	if not attackSucceeded then
		error(attackResultOrError, 0)
	end
	local attackResult = attackResultOrError
	if expeditionExpired then
		attackResult.Succeeded = false
		attackResult.Reason = "ExpeditionTimedOut"
	end

	local latest = MonsterRosterCoordinator.Get(attacker, attackerSpawnPointId)
	if not latest or latest.State == "Defeated" or latest.State == "Recovering" then
		attackerDefeated = true
		emitTerminal(attackResult, latest, "Recovery", "Defeated")
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
	elseif attackResult.Reason == "Cancelled"
		or attackResult.Reason == "ExpeditionTimedOut"
	then
		endReason = "Cancelled"
	else
		endReason = "Failed"
	end
	emitTerminal(attackResult, latest, "Return", endReason)
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
