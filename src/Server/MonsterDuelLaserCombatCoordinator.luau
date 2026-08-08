--[[
	职责：编排 Battle 场景两只怪兽的激光对波决斗。
	输入：攻守双方、动画/VFX 配置、对波时长、胜者推进时长和取消回调。
	输出：胜者、死亡结果和稳定失败原因。
	内部算法：双方同时蓄力，以两只怪兽 Beam.Attachment0 发射点的中点作为碰撞点；
	N 秒后按等级决定胜者，双方激光终点在 M 秒内共同推进到败者发射点，
	使胜者变长、败者变短；到达后由服务端提交致死伤害。
	不负责：创建 Battle 场景、相遇移动、建筑攻击、奖励、回城或镜头控制。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ContinuousAtomicLaserPresentation = require(
	script.Parent.ContinuousAtomicLaserPresentation
)
local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local GodzillaService = require(script.Parent.GodzillaService)
local MonsterCombatDiagnosticLog = require(script.Parent.MonsterCombatDiagnosticLog)
local MonsterDamageCoordinator = require(script.Parent.MonsterDamageCoordinator)
local MonsterAttackVFXController = require(script.Parent.MonsterAttackVFXController)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local MonsterDuelOutcomeRules = require(
	ReplicatedStorage.Shared.Monster.MonsterDuelOutcomeRules
)

local MonsterDuelLaserCombatCoordinator = {}

export type Combatant = {
	Player: Player,
	SpawnPointId: string,
}

export type AnimationConfig = {
	Animations: { [string]: number },
	AttackEffects: { [string]: string },
	HitProgress: number,
	Speed: number,
}

export type CombatConfig = {
	Animation: AnimationConfig,
}

export type ExecuteOptions = {
	TraceId: string,
	AttackerConfig: CombatConfig,
	DefenderConfig: CombatConfig,
	AttackerResumeState: string,
	DefenderResumeState: string,
	LaserDuration: number,
	LaserPushDuration: number,
	WatchdogDuration: number,
	IsCancelled: (() -> boolean)?,
	OnDefeated: ((Player, string, MonsterDamageCoordinator.DamageSource) -> ())?,
	SetMoving: ((Model, boolean, number?) -> ())?,
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
	if isDefeated(combatant) then
		return
	end
	local latest = MonsterRosterCoordinator.Get(combatant.Player, combatant.SpawnPointId)
	if not latest or latest.State == state then
		return
	end
	local restored = MonsterRosterCoordinator.Transition(
		combatant.Player,
		combatant.SpawnPointId,
		state
	)
	if not restored.Succeeded then
		warn("激光决斗恢复怪兽状态失败：", restored.Reason)
	end
end

function MonsterDuelLaserCombatCoordinator.Execute(
	attacker: Combatant,
	defender: Combatant,
	options: ExecuteOptions
): CombatResult
	assert(attacker.Player:IsA("Player") and defender.Player:IsA("Player"), "战斗双方必须是 Player")
	assert(attacker.Player ~= defender.Player, "不能与自己的怪兽战斗")
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.TraceId) == "string" and options.TraceId ~= "", "TraceId 无效")
	assert(type(options.AttackerConfig) == "table", "AttackerConfig 必须是 table")
	assert(type(options.DefenderConfig) == "table", "DefenderConfig 必须是 table")
	assert(isPositive(options.LaserDuration), "LaserDuration 必须大于 0")
	assert(isPositive(options.LaserPushDuration), "LaserPushDuration 必须大于 0")
	assert(
		isPositive(options.WatchdogDuration)
			and options.WatchdogDuration > options.LaserDuration + options.LaserPushDuration,
		"WatchdogDuration 必须大于激光总时长"
	)

	local attackerRecord = MonsterRosterCoordinator.Get(
		attacker.Player,
		attacker.SpawnPointId
	)
	local defenderRecord = MonsterRosterCoordinator.Get(
		defender.Player,
		defender.SpawnPointId
	)
	if not attackerRecord or not attackerRecord.Model then
		return makeResult(false, "AttackerUnavailable", nil, false, false)
	end
	if not defenderRecord or not defenderRecord.Model then
		return makeResult(false, "DefenderUnavailable", nil, false, false)
	end

	local attackerAnimation = options.AttackerConfig.Animation
	local defenderAnimation = options.DefenderConfig.Animation
	local attackerAssetId = attackerAnimation
		and attackerAnimation.Animations
		and attackerAnimation.Animations.AtomicAttack
	local defenderAssetId = defenderAnimation
		and defenderAnimation.Animations
		and defenderAnimation.Animations.AtomicAttack
	local attackerEffectName = attackerAnimation
		and attackerAnimation.AttackEffects
		and attackerAnimation.AttackEffects.AtomicAttack
	local defenderEffectName = defenderAnimation
		and defenderAnimation.AttackEffects
		and defenderAnimation.AttackEffects.AtomicAttack
	if type(attackerAssetId) ~= "number" or attackerAssetId <= 0 then
		return makeResult(false, "AttackerAtomicAttackUnavailable", nil, false, false)
	end
	if type(defenderAssetId) ~= "number" or defenderAssetId <= 0 then
		return makeResult(false, "DefenderAtomicAttackUnavailable", nil, false, false)
	end
	if type(attackerEffectName) ~= "string" or attackerEffectName == "" then
		return makeResult(false, "AttackerAtomicEffectUnavailable", nil, false, false)
	end
	if type(defenderEffectName) ~= "string" or defenderEffectName == "" then
		return makeResult(false, "DefenderAtomicEffectUnavailable", nil, false, false)
	end

	local attackerTransition = MonsterRosterCoordinator.Transition(
		attacker.Player,
		attacker.SpawnPointId,
		"FightingMonster"
	)
	if not attackerTransition.Succeeded then
		return makeResult(false, attackerTransition.Reason, nil, false, false)
	end
	local defenderTransition = MonsterRosterCoordinator.Transition(
		defender.Player,
		defender.SpawnPointId,
		"FightingMonster"
	)
	if not defenderTransition.Succeeded then
		restoreState(attacker, options.AttackerResumeState)
		return makeResult(false, defenderTransition.Reason, nil, false, false)
	end

	local function stopMotion(combatant: Combatant)
		local record = MonsterRosterCoordinator.Get(combatant.Player, combatant.SpawnPointId)
		if not record or not record.Model then
			return
		end
		GodzillaMoveService.Cancel(record.Model)
		if options.SetMoving then
			options.SetMoving(record.Model, false, nil)
		else
			GodzillaService.StopMoving(record.Model)
		end
	end
	stopMotion(attacker)
	stopMotion(defender)

	local function resolveEmitterMidpoint(): Vector3?
		local attackerEmitterPosition = MonsterAttackVFXController.GetSourcePosition(
			attackerRecord.Model,
			attackerEffectName
		)
		local defenderEmitterPosition = MonsterAttackVFXController.GetSourcePosition(
			defenderRecord.Model,
			defenderEffectName
		)
		if not attackerEmitterPosition or not defenderEmitterPosition then
			return nil
		end
		return attackerEmitterPosition:Lerp(defenderEmitterPosition, 0.5)
	end

	local watchdogDeadline = workspace:GetServerTimeNow() + options.WatchdogDuration
	local localAbort = false
	local abortReason: string? = nil
	local attackerLaserSession: ContinuousAtomicLaserPresentation.Session? = nil
	local defenderLaserSession: ContinuousAtomicLaserPresentation.Session? = nil

	local function pollCancelled(): boolean
		if localAbort then
			return true
		end
		if options.IsCancelled then
			local succeeded, cancelledOrError = pcall(options.IsCancelled)
			if not succeeded then
				abortReason = "CancellationCheckFailed"
				localAbort = true
				return true
			end
			if cancelledOrError then
				abortReason = "Cancelled"
				localAbort = true
				return true
			end
		end
		return false
	end

	local function stopLasers()
		if attackerLaserSession then
			attackerLaserSession.Stop()
			attackerLaserSession = nil
		end
		if defenderLaserSession then
			defenderLaserSession.Stop()
			defenderLaserSession = nil
		end
	end

	local function emitFinished(result: CombatResult)
		local latestAttacker = MonsterRosterCoordinator.Get(
			attacker.Player,
			attacker.SpawnPointId
		)
		local latestDefender = MonsterRosterCoordinator.Get(
			defender.Player,
			defender.SpawnPointId
		)
		MonsterCombatDiagnosticLog.Emit("DUEL_FINISHED", {
			TraceId = options.TraceId,
			DuelMode = "Laser",
			Succeeded = result.Succeeded,
			Reason = result.Reason or "None",
			Winner = result.Winner or "None",
			AttackerDefeated = result.AttackerDefeated,
			DefenderDefeated = result.DefenderDefeated,
			AttackerState = if latestAttacker then latestAttacker.State else "None",
			AttackerHealth = if latestAttacker then latestAttacker.Health else 0,
			DefenderState = if latestDefender then latestDefender.State else "None",
			DefenderHealth = if latestDefender then latestDefender.Health else 0,
		})
	end

	local function finish(result: CombatResult): CombatResult
		stopLasers()
		emitFinished(result)
		return result
	end

	local initialTargetPosition = resolveEmitterMidpoint()
	if not initialTargetPosition then
		restoreState(attacker, options.AttackerResumeState)
		restoreState(defender, options.DefenderResumeState)
		return finish(makeResult(
			false,
			"AtomicAttackEmitterUnavailable",
			nil,
			isDefeated(attacker),
			isDefeated(defender)
		))
	end

	local startedCount = 0
	local startError: string? = nil
	local function startLaser(
		model: Model,
		assetId: number,
		effectName: string,
		animation: AnimationConfig,
		assign: (ContinuousAtomicLaserPresentation.Session) -> ()
	)
		task.spawn(function()
			local succeeded, sessionOrError, reason = pcall(
				ContinuousAtomicLaserPresentation.Start,
				model,
				assetId,
				effectName,
				initialTargetPosition,
				{
					HoldProgress = animation.HitProgress,
					Speed = animation.Speed,
					ResolveTargetPosition = resolveEmitterMidpoint,
					IsCancelled = pollCancelled,
				}
			)
			if succeeded and sessionOrError then
				assign(sessionOrError)
			elseif startError == nil then
				startError = if succeeded
					then reason or "AtomicAttackInterrupted"
					else "AtomicAttackPresentationFailed"
				localAbort = true
			end
			startedCount += 1
		end)
	end

	startLaser(
		attackerRecord.Model,
		attackerAssetId,
		attackerEffectName,
		attackerAnimation,
		function(session)
			attackerLaserSession = session
		end
	)
	startLaser(
		defenderRecord.Model,
		defenderAssetId,
		defenderEffectName,
		defenderAnimation,
		function(session)
			defenderLaserSession = session
		end
	)

	while startedCount < 2 do
		local currentTargetPosition = resolveEmitterMidpoint()
		if currentTargetPosition then
			if attackerLaserSession then
				attackerLaserSession.UpdateTarget(currentTargetPosition)
			end
			if defenderLaserSession then
				defenderLaserSession.UpdateTarget(currentTargetPosition)
			end
		end
		if pollCancelled() then
			break
		end
		if workspace:GetServerTimeNow() >= watchdogDeadline then
			abortReason = "DuelLaserWatchdogTimeout"
			localAbort = true
			break
		end
		RunService.Heartbeat:Wait()
	end
	while startedCount < 2 do
		local currentTargetPosition = resolveEmitterMidpoint()
		if currentTargetPosition then
			if attackerLaserSession then
				attackerLaserSession.UpdateTarget(currentTargetPosition)
			end
			if defenderLaserSession then
				defenderLaserSession.UpdateTarget(currentTargetPosition)
			end
		end
		RunService.Heartbeat:Wait()
	end
	if startError ~= nil or not attackerLaserSession or not defenderLaserSession then
		restoreState(attacker, options.AttackerResumeState)
		restoreState(defender, options.DefenderResumeState)
		return finish(makeResult(
			false,
			startError or abortReason or "AtomicAttackPresentationFailed",
			nil,
			isDefeated(attacker),
			isDefeated(defender)
		))
	end

	local attackerEmitterPosition = attackerLaserSession.GetEmitterPosition()
	local defenderEmitterPosition = defenderLaserSession.GetEmitterPosition()
	if not attackerEmitterPosition or not defenderEmitterPosition then
		restoreState(attacker, options.AttackerResumeState)
		restoreState(defender, options.DefenderResumeState)
		return finish(makeResult(
			false,
			"AtomicAttackEmitterUnavailable",
			nil,
			isDefeated(attacker),
			isDefeated(defender)
		))
	end
	local collisionPosition = attackerEmitterPosition:Lerp(
		defenderEmitterPosition,
		0.5
	)
	attackerLaserSession.UpdateTarget(collisionPosition)
	defenderLaserSession.UpdateTarget(collisionPosition)

	local function waitFor(seconds: number): (boolean, string?)
		local deadline = workspace:GetServerTimeNow() + seconds
		while workspace:GetServerTimeNow() < deadline do
			if pollCancelled() then
				return false, abortReason or "Cancelled"
			end
			if workspace:GetServerTimeNow() >= watchdogDeadline then
				return false, "DuelLaserWatchdogTimeout"
			end
			RunService.Heartbeat:Wait()
		end
		return true, nil
	end

	local waveCompleted, waveReason = waitFor(options.LaserDuration)
	if not waveCompleted then
		restoreState(attacker, options.AttackerResumeState)
		restoreState(defender, options.DefenderResumeState)
		return finish(makeResult(
			false,
			waveReason,
			nil,
			isDefeated(attacker),
			isDefeated(defender)
		))
	end

	local latestAttacker = MonsterRosterCoordinator.Get(
		attacker.Player,
		attacker.SpawnPointId
	)
	local latestDefender = MonsterRosterCoordinator.Get(
		defender.Player,
		defender.SpawnPointId
	)
	if not latestAttacker or not latestAttacker.Model then
		return finish(makeResult(false, "AttackerUnavailable", nil, true, false))
	end
	if not latestDefender or not latestDefender.Model then
		return finish(makeResult(false, "DefenderUnavailable", nil, false, true))
	end
	local attackerDefinition = MonsterCatalog.Get(latestAttacker.MonsterKey)
	local defenderDefinition = MonsterCatalog.Get(latestDefender.MonsterKey)
	if not attackerDefinition or not defenderDefinition then
		restoreState(attacker, options.AttackerResumeState)
		restoreState(defender, options.DefenderResumeState)
		return finish(makeResult(false, "MonsterLevelUnavailable", nil, false, false))
	end

	local winner = MonsterDuelOutcomeRules.Resolve(
		attackerDefinition.Level,
		defenderDefinition.Level
	)
	local winnerSession = if winner == "Attacker"
		then attackerLaserSession
		else defenderLaserSession
	local loserSession = if winner == "Attacker"
		then defenderLaserSession
		else attackerLaserSession
	local loserModel = if winner == "Attacker"
		then latestDefender.Model
		else latestAttacker.Model
	if not winnerSession or not loserSession or not loserModel then
		restoreState(attacker, options.AttackerResumeState)
		restoreState(defender, options.DefenderResumeState)
		return finish(makeResult(false, "LaserSessionUnavailable", nil, false, false))
	end

	local loserEmitterPosition = if winner == "Attacker"
		then defenderEmitterPosition
		else attackerEmitterPosition
	local pushStart = workspace:GetServerTimeNow()
	while true do
		if pollCancelled() then
			restoreState(attacker, options.AttackerResumeState)
			restoreState(defender, options.DefenderResumeState)
			return finish(makeResult(
				false,
				abortReason or "Cancelled",
				nil,
				isDefeated(attacker),
				isDefeated(defender)
			))
		end
		if workspace:GetServerTimeNow() >= watchdogDeadline then
			restoreState(attacker, options.AttackerResumeState)
			restoreState(defender, options.DefenderResumeState)
			return finish(makeResult(
				false,
				"DuelLaserWatchdogTimeout",
				nil,
				isDefeated(attacker),
				isDefeated(defender)
			))
		end
		local alpha = math.clamp(
			(workspace:GetServerTimeNow() - pushStart) / options.LaserPushDuration,
			0,
			1
		)
		local latestLoser = MonsterRosterCoordinator.Get(
			if winner == "Attacker" then defender.Player else attacker.Player,
			if winner == "Attacker" then defender.SpawnPointId else attacker.SpawnPointId
		)
		if not latestLoser or not latestLoser.Model then
			break
		end
		local nextCollisionPosition = collisionPosition:Lerp(
			loserEmitterPosition,
			alpha
		)
		-- 两条激光共用同一个碰撞点：胜者变长、败者同步变短，直到推进到败者发射点。
		attackerLaserSession.UpdateTarget(nextCollisionPosition)
		defenderLaserSession.UpdateTarget(nextCollisionPosition)
		if alpha >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end

	local loserPlayer = if winner == "Attacker" then defender.Player else attacker.Player
	local loserSpawnPointId = if winner == "Attacker"
		then defender.SpawnPointId
		else attacker.SpawnPointId
	local loserRecord = MonsterRosterCoordinator.Get(loserPlayer, loserSpawnPointId)
	if not loserRecord then
		restoreState(attacker, options.AttackerResumeState)
		restoreState(defender, options.DefenderResumeState)
		return finish(makeResult(false, "LoserUnavailable", nil, false, false))
	end
	local damageResult = MonsterDamageCoordinator.ApplyDamage(
		loserPlayer,
		loserSpawnPointId,
		{
			OwnerUserId = if winner == "Attacker" then attacker.Player.UserId else defender.Player.UserId,
			SourceId = if winner == "Attacker" then attacker.SpawnPointId else defender.SpawnPointId,
			Kind = "Monster",
			TraceId = options.TraceId,
		},
		math.max(loserRecord.Health, 1),
		{ OnDefeated = options.OnDefeated }
	)
	if not damageResult.Succeeded or not damageResult.Defeated then
		restoreState(attacker, options.AttackerResumeState)
		restoreState(defender, options.DefenderResumeState)
		return finish(makeResult(
			false,
			damageResult.Reason or "LaserDefeatFailed",
			nil,
			isDefeated(attacker),
			isDefeated(defender)
		))
	end

	if winner == "Attacker" then
		restoreState(attacker, options.AttackerResumeState)
	else
		restoreState(defender, options.DefenderResumeState)
	end
	return finish(makeResult(
		true,
		nil,
		winner,
		winner == "Defender",
		winner == "Attacker"
	))
end

return MonsterDuelLaserCombatCoordinator
