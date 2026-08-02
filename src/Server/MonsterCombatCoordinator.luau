local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackAnimationPlayer = require(script.Parent.AttackAnimationPlayer)
local AttackAnimationSelector = require(script.Parent.AttackAnimationSelector)
local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local MonsterDamageCoordinator = require(script.Parent.MonsterDamageCoordinator)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterCombatGeometry = require(ReplicatedStorage.Shared.Monster.MonsterCombatGeometry)

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
		TurnDuration: number,
	},
	Animation: {
		Animations: { [string]: number },
		AttackSequence: { string },
		SelectionMode: AttackAnimationSelector.SelectionMode,
		HitProgress: number,
		Speed: number,
	},
}

export type ExecuteOptions = {
	AttackerConfig: CombatConfig,
	DefenderConfig: CombatConfig,
	ApproachingSide: "Attacker" | "Defender",
	FirstStrike: "Attacker" | "Defender",
	AttackerResumeState: string,
	DefenderResumeState: string,
	IsCancelled: (() -> boolean)?,
	OnDefeated: ((Player, string, MonsterDamageCoordinator.DamageSource) -> ())?,
	SetMoving: ((Model, boolean) -> ())?,
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
	local pose = MonsterCombatGeometry.ResolvePose(
		moverRecord.Model,
		targetRecord.Model,
		moverConfig.Movement.DesiredGap
	)
	local moved = GodzillaMoveService.MoveTo(moverRecord.Model, pose.Position, {
		MoveSpeed = moverConfig.Movement.MoveSpeed,
		TurnDuration = moverConfig.Movement.TurnDuration,
		SetMoving = function(isMoving)
			if options.SetMoving then
				options.SetMoving(moverRecord.Model, isMoving)
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
	GodzillaMoveService.FaceTo(
		attackerLatest.Model,
		defenderLatest.Model:GetPivot().Position,
		options.AttackerConfig.Movement.TurnDuration
	)
	GodzillaMoveService.FaceTo(
		defenderLatest.Model,
		attackerLatest.Model:GetPivot().Position,
		options.DefenderConfig.Movement.TurnDuration
	)
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
		AttackAnimationPlayer.Play,
		sourceRecord.Model,
		choice.AssetId,
		{
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
	if playbackOrError.Cancelled then
		return false, "CombatCancelled"
	end
	if not playbackOrError.HitTriggered then
		return false, "AttackInterrupted"
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
	assert(
		options.FirstStrike == "Attacker" or options.FirstStrike == "Defender",
		"FirstStrike 必须是 Attacker 或 Defender"
	)
	validateConfig(options.AttackerConfig)
	validateConfig(options.DefenderConfig)

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

	local positioned, positionReason = positionCombatants(attacker, defender, options)
	if not positioned then
		restoreState(attacker, options.AttackerResumeState)
		restoreState(defender, options.DefenderResumeState)
		return makeResult(false, positionReason, nil, isDefeated(attacker), isDefeated(defender))
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
			return makeResult(false, "CombatCancelled", nil, isDefeated(attacker), isDefeated(defender))
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
			return makeResult(true, nil, winner, attackerDefeated, defenderDefeated)
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

		local attacked, attackReason = playAttack(source, target, config, options)
		if not attacked and attackReason ~= "TargetUnavailable" then
			restoreState(attacker, options.AttackerResumeState)
			restoreState(defender, options.DefenderResumeState)
			return makeResult(false, attackReason, nil, isDefeated(attacker), isDefeated(defender))
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
