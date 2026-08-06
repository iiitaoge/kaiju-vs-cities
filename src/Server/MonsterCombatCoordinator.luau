local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackAnimationSelector = require(script.Parent.AttackAnimationSelector)
local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local GodzillaService = require(script.Parent.GodzillaService)
local MonsterDamageCoordinator = require(script.Parent.MonsterDamageCoordinator)
local MonsterCombatDiagnosticLog = require(script.Parent.MonsterCombatDiagnosticLog)
local MonsterAttackPresentationPlayer = require(
	script.Parent.MonsterAttackPresentationPlayer
)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local MonsterCombatGeometry = require(ReplicatedStorage.Shared.Monster.MonsterCombatGeometry)
local MonsterDuelOutcomeRules = require(
	ReplicatedStorage.Shared.Monster.MonsterDuelOutcomeRules
)

local MonsterCombatCoordinator = {}

export type Combatant = {
	Player: Player,
	SpawnPointId: string,
}

export type CombatConfig = {
	Damage: number,
	AttackInterval: number,
	Movement: {
		DesiredGap: number,
		MaxGap: number,
		MoveSpeed: number,
		MaxTravelDuration: number?,
		TimingSafetyMargin: number?,
		TurnDuration: number,
	},
	Animation: {
		Animations: { [string]: number },
		AttackSequence: { string },
		AttackEffects: { [string]: string },
		SelectionMode: AttackAnimationSelector.SelectionMode,
		HitProgress: number,
		Speed: number,
	},
}

export type ExecuteOptions = {
	TraceId: string,
	AttackerConfig: CombatConfig,
	DefenderConfig: CombatConfig,
	ApproachingSide: "Attacker" | "Defender",
	FirstStrike: "Attacker" | "Defender",
	AttackerResumeState: string,
	DefenderResumeState: string,
	IsCancelled: (() -> boolean)?,
	OnDefeated: ((Player, string, MonsterDamageCoordinator.DamageSource) -> ())?,
	SetMoving: ((Model, boolean, number?) -> ())?,
	ResolutionDuration: number,
	WatchdogDuration: number,
}

export type CombatResult = {
	Succeeded: boolean,
	Reason: string?,
	Winner: "Attacker" | "Defender" | nil,
	AttackerDefeated: boolean,
	DefenderDefeated: boolean,
}

local function isPositive(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value > 0
end

local function validateConfig(config: CombatConfig)
	assert(type(config) == "table", "CombatConfig 必须是 table")
	assert(isPositive(config.Damage), "Damage 必须大于 0")
	assert(isPositive(config.AttackInterval), "AttackInterval 必须大于 0")
	assert(type(config.Movement) == "table", "Movement 必须是 table")
	assert(config.Movement.DesiredGap >= 0, "DesiredGap 必须大于等于 0")
	assert(config.Movement.MaxGap >= config.Movement.DesiredGap, "MaxGap 不能小于 DesiredGap")
	assert(isPositive(config.Movement.MoveSpeed), "MoveSpeed 必须大于 0")
	assert(isPositive(config.Movement.TurnDuration), "TurnDuration 必须大于 0")
	assert(type(config.Animation) == "table", "Animation 必须是 table")
	assert(type(config.Animation.Animations) == "table", "Animations 必须是 table")
	assert(type(config.Animation.AttackSequence) == "table", "AttackSequence 必须是 table")
	assert(type(config.Animation.AttackEffects) == "table", "AttackEffects 必须是 table")
	assert(#config.Animation.AttackSequence > 0, "AttackSequence 不能为空")
	assert(
		type(config.Animation.HitProgress) == "number"
			and config.Animation.HitProgress >= 0
			and config.Animation.HitProgress <= 1,
		"HitProgress 必须在 0 到 1 之间"
	)
	assert(isPositive(config.Animation.Speed), "Animation.Speed 必须大于 0")
end

local function makeResult(
	succeeded: boolean,
	reason: string?,
	winner: "Attacker" | "Defender"?,
	attackerDefeated: boolean,
	defenderDefeated: boolean
): CombatResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		Winner = winner,
		AttackerDefeated = attackerDefeated,
		DefenderDefeated = defenderDefeated,
	}
end

local function isDefeated(combatant: Combatant): boolean
	local record = MonsterRosterCoordinator.Get(combatant.Player, combatant.SpawnPointId)
	return not record
		or record.State == "Defeated"
		or record.State == "Recovering"
		or record.Health <= 0
		or not record.Model
end

local function restoreState(combatant: Combatant, state: string)
	if not isDefeated(combatant) then
		local result = MonsterRosterCoordinator.Transition(
			combatant.Player,
			combatant.SpawnPointId,
			state
		)
		if not result.Succeeded then
			warn("恢复怪兽战斗前状态失败：", result.Reason)
		end
	end
end

local function positionCombatants(
	attacker: Combatant,
	defender: Combatant,
	options: ExecuteOptions
): (boolean, string?)
	local attackerRecord = MonsterRosterCoordinator.Get(attacker.Player, attacker.SpawnPointId)
	local defenderRecord = MonsterRosterCoordinator.Get(defender.Player, defender.SpawnPointId)
	if not attackerRecord or not attackerRecord.Model then
		return false, "AttackerUnavailable"
	end
	if not defenderRecord or not defenderRecord.Model then
		return false, "DefenderUnavailable"
	end

	local moverRecord = if options.ApproachingSide == "Attacker" then attackerRecord else defenderRecord
	local targetRecord = if options.ApproachingSide == "Attacker" then defenderRecord else attackerRecord
	local moverConfig = if options.ApproachingSide == "Attacker"
		then options.AttackerConfig
		else options.DefenderConfig
	local targetConfig = if options.ApproachingSide == "Attacker"
		then options.DefenderConfig
		else options.AttackerConfig

	-- ResolvePose 会按接敌方最终面向目标时的包围盒计算站位，因此静止方也必须
	-- 先进入最终朝向。否则大型非正方形模型在站位完成后转向，会让已经求出的边缘距离失效。
	local targetFaced = GodzillaMoveService.FaceTo(
		targetRecord.Model,
		moverRecord.Model:GetPivot().Position,
		targetConfig.Movement.TurnDuration
	)
	if not targetFaced then
		return false, "FaceTargetIntoCombatFailed"
	end

	attackerRecord = MonsterRosterCoordinator.Get(attacker.Player, attacker.SpawnPointId)
	defenderRecord = MonsterRosterCoordinator.Get(defender.Player, defender.SpawnPointId)
	if not attackerRecord or not attackerRecord.Model or not defenderRecord or not defenderRecord.Model then
		return false, "CombatantUnavailable"
	end
	moverRecord = if options.ApproachingSide == "Attacker" then attackerRecord else defenderRecord
	targetRecord = if options.ApproachingSide == "Attacker" then defenderRecord else attackerRecord
	local pose = MonsterCombatGeometry.ResolvePose(
		moverRecord.Model,
		targetRecord.Model,
		moverConfig.Movement.DesiredGap
	)
	local moved = GodzillaMoveService.MoveTo(moverRecord.Model, pose.Position, {
		MoveSpeed = moverConfig.Movement.MoveSpeed,
		MaxTravelDuration = moverConfig.Movement.MaxTravelDuration,
		TimingSafetyMargin = moverConfig.Movement.TimingSafetyMargin,
		TurnDuration = moverConfig.Movement.TurnDuration,
		SetMoving = function(isMoving, moveSpeed)
			if options.SetMoving then
				options.SetMoving(moverRecord.Model, isMoving, moveSpeed)
			end
		end,
	})
	if not moved then
		return false, "MoveIntoCombatRangeFailed"
	end

	local attackerLatest = MonsterRosterCoordinator.Get(attacker.Player, attacker.SpawnPointId)
	local defenderLatest = MonsterRosterCoordinator.Get(defender.Player, defender.SpawnPointId)
	if not attackerLatest or not attackerLatest.Model or not defenderLatest or not defenderLatest.Model then
		return false, "CombatantUnavailable"
	end
	local moverLatest = if options.ApproachingSide == "Attacker" then attackerLatest else defenderLatest
	local targetLatest = if options.ApproachingSide == "Attacker" then defenderLatest else attackerLatest
	local moverFaced = GodzillaMoveService.FaceTo(
		moverLatest.Model,
		pose.LookAtPosition,
		moverConfig.Movement.TurnDuration
	)
	if not moverFaced then
		return false, "FaceMoverIntoCombatFailed"
	end

	local finalGap = MonsterCombatGeometry.GetGap(moverLatest.Model, targetLatest.Model)
	local maxAllowedGap = math.min(
		options.AttackerConfig.Movement.MaxGap,
		options.DefenderConfig.Movement.MaxGap
	)
	MonsterCombatDiagnosticLog.Emit("DUEL_POSITIONED", {
		TraceId = options.TraceId,
		ApproachingSide = options.ApproachingSide,
		DesiredGap = moverConfig.Movement.DesiredGap,
		FinalGap = finalGap,
		MaxAllowedGap = maxAllowedGap,
		InRange = finalGap <= maxAllowedGap,
	})
	if finalGap > maxAllowedGap then
		return false, "CombatPositionOutOfRange"
	end
	return true, nil
end

local function playAttack(
	source: Combatant,
	target: Combatant,
	config: CombatConfig,
	options: ExecuteOptions
): (boolean, string?)
	local sourceRecord = MonsterRosterCoordinator.Get(source.Player, source.SpawnPointId)
	local targetRecord = MonsterRosterCoordinator.Get(target.Player, target.SpawnPointId)
	if not sourceRecord or not sourceRecord.Model then
		return false, "SourceUnavailable"
	end
	if not targetRecord or not targetRecord.Model then
		return false, "TargetUnavailable"
	end
	if MonsterCombatGeometry.GetGap(sourceRecord.Model, targetRecord.Model)
		> config.Movement.MaxGap then
		return false, "TargetOutOfRange"
	end

	local choice = AttackAnimationSelector.Next(
		sourceRecord.Model,
		config.Animation.Animations,
		config.Animation.AttackSequence,
		{ Mode = config.Animation.SelectionMode }
	)
	local damageResult = nil
	local played, playbackOrError = pcall(
		MonsterAttackPresentationPlayer.Play,
		sourceRecord.Model,
		choice.AssetId,
		{
			EffectName = config.Animation.AttackEffects[choice.Name],
			ResolveTargetPosition = function()
				local latest = MonsterRosterCoordinator.Get(
					target.Player,
					target.SpawnPointId
				)
				return if latest and latest.Model
					then latest.Model:GetPivot().Position
					else nil
			end,
			HitProgress = config.Animation.HitProgress,
			Speed = config.Animation.Speed,
			Priority = Enum.AnimationPriority.Action,
			IsCancelled = function()
				return (options.IsCancelled and options.IsCancelled())
					or isDefeated(source)
					or isDefeated(target)
			end,
		},
		function()
			damageResult = MonsterDamageCoordinator.ApplyDamage(
				target.Player,
				target.SpawnPointId,
				{
					OwnerUserId = source.Player.UserId,
					SourceId = source.SpawnPointId,
					Kind = "Monster",
					TraceId = options.TraceId,
				},
				config.Damage,
				{ OnDefeated = options.OnDefeated }
			)
		end
	)
	if not played then
		warn("怪兽对战动画失败：", playbackOrError)
		return false, "AttackAnimationFailed"
	end
	-- 命中结算优先于动画的后续取消。致死伤害会立即销毁目标模型，
	-- 从而主动停止剩余动画，但已经提交的这一击仍然是有效攻击。
	if not playbackOrError.HitTriggered then
		return false, if playbackOrError.Cancelled
			then "CombatCancelled"
			else "AttackInterrupted"
	end
	if not damageResult or not damageResult.Succeeded then
		return false, if damageResult then damageResult.Reason else "DamageNotApplied"
	end
	return true, nil
end

-- 输入：进攻怪兽、防守怪兽、双方显式战斗配置和战后恢复状态。
-- 输出：胜者、双方死亡结果和失败原因。
-- 内部算法：安排接敌站位，双方按各自攻击间隔轮流播放动画并在命中帧结算伤害。
function MonsterCombatCoordinator.Execute(
	attacker: Combatant,
	defender: Combatant,
	options: ExecuteOptions
): CombatResult
	assert(attacker.Player:IsA("Player") and defender.Player:IsA("Player"), "战斗双方必须是 Player")
	assert(attacker.Player ~= defender.Player, "不能与自己的怪兽战斗")
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.TraceId) == "string" and options.TraceId ~= "", "TraceId 无效")
	assert(
		options.FirstStrike == "Attacker" or options.FirstStrike == "Defender",
		"FirstStrike 必须是 Attacker 或 Defender"
	)
	validateConfig(options.AttackerConfig)
	validateConfig(options.DefenderConfig)
	assert(isPositive(options.ResolutionDuration), "ResolutionDuration 必须大于 0")
	assert(
		isPositive(options.WatchdogDuration)
			and options.WatchdogDuration > options.ResolutionDuration,
		"WatchdogDuration 必须大于 ResolutionDuration"
	)

	local combatStartedAt = workspace:GetServerTimeNow()
	local finished = false
	local resolutionRequested = false
	local watchdogRequested = false
	local function finish(result: CombatResult): CombatResult
		finished = true
		local attackerRecord = MonsterRosterCoordinator.Get(attacker.Player, attacker.SpawnPointId)
		local defenderRecord = MonsterRosterCoordinator.Get(defender.Player, defender.SpawnPointId)
		MonsterCombatDiagnosticLog.Emit("DUEL_FINISHED", {
			TraceId = options.TraceId,
			AttackerUserId = attacker.Player.UserId,
			AttackerSpawnPointId = attacker.SpawnPointId,
			DefenderUserId = defender.Player.UserId,
			DefenderSpawnPointId = defender.SpawnPointId,
			Succeeded = result.Succeeded,
			Reason = result.Reason or "None",
			Winner = result.Winner or "None",
			AttackerDefeated = result.AttackerDefeated,
			DefenderDefeated = result.DefenderDefeated,
			AttackerState = if attackerRecord then attackerRecord.State else "None",
			AttackerHealth = if attackerRecord then attackerRecord.Health else 0,
			AttackerModelExists = attackerRecord ~= nil and attackerRecord.Model ~= nil,
			DefenderState = if defenderRecord then defenderRecord.State else "None",
			DefenderHealth = if defenderRecord then defenderRecord.Health else 0,
			DefenderModelExists = defenderRecord ~= nil and defenderRecord.Model ~= nil,
			ElapsedSeconds = workspace:GetServerTimeNow() - combatStartedAt,
		})
		return result
	end
	local function cancelMotion(combatant: Combatant)
		local record = MonsterRosterCoordinator.Get(combatant.Player, combatant.SpawnPointId)
		if record and record.Model then
			GodzillaMoveService.Cancel(record.Model)
			if options.SetMoving then
				options.SetMoving(record.Model, false, nil)
			else
				GodzillaService.StopMoving(record.Model)
			end
		end
	end
	local function requestResolution(watchdog: boolean)
		if finished then
			return
		end
		resolutionRequested = true
		watchdogRequested = watchdogRequested or watchdog
		cancelMotion(attacker)
		cancelMotion(defender)
	end
	task.delay(options.ResolutionDuration, function()
		requestResolution(false)
	end)
	task.delay(options.WatchdogDuration, function()
		requestResolution(true)
	end)

	local attackerTransition = MonsterRosterCoordinator.Transition(
		attacker.Player,
		attacker.SpawnPointId,
		"FightingMonster"
	)
	if not attackerTransition.Succeeded then
		return finish(makeResult(false, attackerTransition.Reason, nil, false, false))
	end
	local defenderTransition = MonsterRosterCoordinator.Transition(
		defender.Player,
		defender.SpawnPointId,
		"FightingMonster"
	)
	if not defenderTransition.Succeeded then
		restoreState(attacker, options.AttackerResumeState)
		return finish(makeResult(false, defenderTransition.Reason, nil, false, false))
	end
	for _, combatant in { attacker, defender } do
		local record = MonsterRosterCoordinator.Get(
			combatant.Player,
			combatant.SpawnPointId
		)
		if record and record.Model then
			GodzillaMoveService.Cancel(record.Model)
			if options.SetMoving then
				options.SetMoving(record.Model, false, nil)
			else
				GodzillaService.StopMoving(record.Model)
			end
		end
	end

	local function resolveByLevel(): CombatResult
		local attackerRecord = MonsterRosterCoordinator.Get(attacker.Player, attacker.SpawnPointId)
		local defenderRecord = MonsterRosterCoordinator.Get(defender.Player, defender.SpawnPointId)
		if not attackerRecord or not defenderRecord then
			return finish(makeResult(false, "CombatantUnavailable", nil, isDefeated(attacker), isDefeated(defender)))
		end
		local attackerDefinition = MonsterCatalog.Get(attackerRecord.MonsterKey)
		local defenderDefinition = MonsterCatalog.Get(defenderRecord.MonsterKey)
		if not attackerDefinition or not defenderDefinition then
			return finish(makeResult(false, "MonsterLevelUnavailable", nil, false, false))
		end
		local winner = MonsterDuelOutcomeRules.Resolve(
			attackerDefinition.Level,
			defenderDefinition.Level
		)
		local winnerCombatant = if winner == "Attacker" then attacker else defender
		local loserCombatant = if winner == "Attacker" then defender else attacker
		local loserRecord = MonsterRosterCoordinator.Get(loserCombatant.Player, loserCombatant.SpawnPointId)
		if not loserRecord then
			return finish(makeResult(false, "CombatantUnavailable", nil, isDefeated(attacker), isDefeated(defender)))
		end
		local damage = math.max(loserRecord.Health, 1)
		MonsterCombatDiagnosticLog.Emit("DUEL_LEVEL_RESOLUTION", {
			TraceId = options.TraceId,
			AttackerSpawnPointId = attacker.SpawnPointId,
			DefenderSpawnPointId = defender.SpawnPointId,
			ResolutionKind = if watchdogRequested then "Watchdog" else "ResolutionTimer",
			AttackerMonsterKey = attackerRecord.MonsterKey,
			AttackerLevel = attackerDefinition.Level,
			AttackerHealth = attackerRecord.Health,
			DefenderMonsterKey = defenderRecord.MonsterKey,
			DefenderLevel = defenderDefinition.Level,
			DefenderHealth = defenderRecord.Health,
			ComputedWinner = winner,
			ComputedLoser = if winner == "Attacker" then "Defender" else "Attacker",
			FatalDamage = damage,
			ElapsedSeconds = workspace:GetServerTimeNow() - combatStartedAt,
		})
		local damageResult = MonsterDamageCoordinator.ApplyDamage(
			loserCombatant.Player,
			loserCombatant.SpawnPointId,
			{
				OwnerUserId = winnerCombatant.Player.UserId,
				SourceId = winnerCombatant.SpawnPointId,
				Kind = "Monster",
				TraceId = options.TraceId,
			},
			damage,
			{ OnDefeated = options.OnDefeated }
		)
		if not damageResult.Succeeded or not damageResult.Defeated then
			restoreState(attacker, options.AttackerResumeState)
			restoreState(defender, options.DefenderResumeState)
			return finish(makeResult(false, damageResult.Reason or "LevelResolutionFailed", nil, isDefeated(attacker), isDefeated(defender)))
		end
		if winner == "Attacker" then
			restoreState(attacker, options.AttackerResumeState)
		else
			restoreState(defender, options.DefenderResumeState)
		end
		return finish(makeResult(
			true,
			if watchdogRequested then "DuelWatchdogResolved" else nil,
			winner,
			winner == "Defender",
			winner == "Attacker"
		))
	end

	local positioned, positionReason = positionCombatants(attacker, defender, options)
	if not positioned then
		if resolutionRequested then
			return resolveByLevel()
		end
		restoreState(attacker, options.AttackerResumeState)
		restoreState(defender, options.DefenderResumeState)
		return finish(makeResult(false, positionReason, nil, isDefeated(attacker), isDefeated(defender)))
	end

	local now = workspace:GetServerTimeNow()
	local nextAttackerAt = if options.FirstStrike == "Attacker"
		then now
		else now + options.AttackerConfig.AttackInterval
	local nextDefenderAt = if options.FirstStrike == "Defender"
		then now
		else now + options.DefenderConfig.AttackInterval
	while true do
		if options.IsCancelled and options.IsCancelled() then
			restoreState(attacker, options.AttackerResumeState)
			restoreState(defender, options.DefenderResumeState)
			return finish(makeResult(false, "CombatCancelled", nil, isDefeated(attacker), isDefeated(defender)))
		end

		local attackerDefeated = isDefeated(attacker)
		local defenderDefeated = isDefeated(defender)
		if attackerDefeated or defenderDefeated then
			local winner = if attackerDefeated then "Defender" else "Attacker"
			if not attackerDefeated then
				restoreState(attacker, options.AttackerResumeState)
			end
			if not defenderDefeated then
				restoreState(defender, options.DefenderResumeState)
			end
			return finish(makeResult(true, nil, winner, attackerDefeated, defenderDefeated))
		end
		-- 已经发生的致死命中优先于同一帧到达的等级判胜计时点。
		if resolutionRequested then
			return resolveByLevel()
		end

		now = workspace:GetServerTimeNow()
		local source = attacker
		local target = defender
		local config = options.AttackerConfig
		if nextDefenderAt < nextAttackerAt then
			source = defender
			target = attacker
			config = options.DefenderConfig
		end
		local nextAt = if source == attacker then nextAttackerAt else nextDefenderAt
		if nextAt > now then
			task.wait(math.min(nextAt - now, 0.1))
			continue
		end

		local combatOptions = table.clone(options)
		combatOptions.IsCancelled = function()
			return resolutionRequested or (options.IsCancelled and options.IsCancelled()) or false
		end
		local attacked, attackReason = playAttack(source, target, config, combatOptions)
		if not attacked and attackReason ~= "TargetUnavailable" then
			if resolutionRequested then
				return resolveByLevel()
			end
			restoreState(attacker, options.AttackerResumeState)
			restoreState(defender, options.DefenderResumeState)
			return finish(makeResult(false, attackReason, nil, isDefeated(attacker), isDefeated(defender)))
		end
		local nextTime = workspace:GetServerTimeNow() + config.AttackInterval
		if source == attacker then
			nextAttackerAt = nextTime
		else
			nextDefenderAt = nextTime
		end
	end
end

return MonsterCombatCoordinator
