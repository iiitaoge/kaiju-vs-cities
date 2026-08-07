--[[
	职责：协调进攻怪兽和防守怪兽从各自出生点移动到相遇中心。
	输入：双方身份、相遇 CFrame、双方移动配置和取消检查。
	输出：双方是否完成相遇，以及稳定失败原因。
	内部算法：按相遇中心和双方包围盒计算中心两侧的停位；双方并行移动，
	到达后互相转身；成功后保留 Encountering 状态，交给战斗协调器切换 FightingMonster。
	不负责：选择防守目标、伤害、胜负、激光、回城或决斗场景。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterCombatGeometry = require(
	ReplicatedStorage.Shared.Monster.MonsterCombatGeometry
)

local MonsterEncounterCoordinator = {}

export type Combatant = {
	Player: Player,
	SpawnPointId: string,
}

export type MovementConfig = {
	DesiredGap: number,
	MaxGap: number,
	MoveSpeed: number,
	MaxTravelDuration: number?,
	TimingSafetyMargin: number?,
	TurnDuration: number,
}

export type ExecuteOptions = {
	TraceId: string,
	EncounterCFrame: CFrame,
	AttackerMovement: MovementConfig,
	DefenderMovement: MovementConfig,
	SetMoving: ((Model, boolean, number?) -> ())?,
	IsCancelled: (() -> boolean)?,
}

export type Result = {
	Succeeded: boolean,
	Reason: string?,
}

local EPSILON = 1e-6

local function result(succeeded: boolean, reason: string?): Result
	return {
		Succeeded = succeeded,
		Reason = reason,
	}
end

local function horizontalUnit(from: Vector3, to: Vector3, fallback: Vector3): Vector3
	local direction = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if direction.Magnitude > EPSILON then
		return direction.Unit
	end
	local fallbackHorizontal = Vector3.new(fallback.X, 0, fallback.Z)
	if fallbackHorizontal.Magnitude > EPSILON then
		return fallbackHorizontal.Unit
	end
	return Vector3.new(1, 0, 0)
end

local function restoreState(combatant: Combatant, state: string)
	local latest = MonsterRosterCoordinator.Get(combatant.Player, combatant.SpawnPointId)
	if not latest or latest.State ~= "Encountering" then
		return
	end
	local restored = MonsterRosterCoordinator.Transition(
		combatant.Player,
		combatant.SpawnPointId,
		state
	)
	if not restored.Succeeded then
		warn("恢复怪兽相遇前状态失败：", restored.Reason)
	end
end

function MonsterEncounterCoordinator.Execute(
	attacker: Combatant,
	defender: Combatant,
	options: ExecuteOptions
): Result
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.TraceId) == "string" and options.TraceId ~= "", "TraceId 无效")
	assert(typeof(options.EncounterCFrame) == "CFrame", "EncounterCFrame 无效")
	assert(type(options.AttackerMovement) == "table", "AttackerMovement 无效")
	assert(type(options.DefenderMovement) == "table", "DefenderMovement 无效")

	local attackerBefore = MonsterRosterCoordinator.Get(
		attacker.Player,
		attacker.SpawnPointId
	)
	local defenderBefore = MonsterRosterCoordinator.Get(
		defender.Player,
		defender.SpawnPointId
	)
	if not attackerBefore or not attackerBefore.Model then
		return result(false, "AttackerUnavailable")
	end
	if not defenderBefore or not defenderBefore.Model then
		return result(false, "DefenderUnavailable")
	end
	local attackerState = attackerBefore.State
	local defenderState = defenderBefore.State

	local attackerTransition = MonsterRosterCoordinator.Transition(
		attacker.Player,
		attacker.SpawnPointId,
		"Encountering"
	)
	if not attackerTransition.Succeeded then
		return result(false, attackerTransition.Reason or "AttackerEncounterTransitionFailed")
	end
	local defenderTransition = MonsterRosterCoordinator.Transition(
		defender.Player,
		defender.SpawnPointId,
		"Encountering"
	)
	if not defenderTransition.Succeeded then
		restoreState(attacker, attackerState)
		return result(false, defenderTransition.Reason or "DefenderEncounterTransitionFailed")
	end

	local attackerModel = attackerTransition.Record and attackerTransition.Record.Model
	local defenderModel = defenderTransition.Record and defenderTransition.Record.Model
	if not attackerModel or not defenderModel then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, "EncounterCombatantUnavailable")
	end

	local attackerStart = attackerModel:GetPivot().Position
	local defenderStart = defenderModel:GetPivot().Position
	local direction = horizontalUnit(
		attackerStart,
		defenderStart,
		options.EncounterCFrame.LookVector
	)
	local desiredGap = math.max(
		options.AttackerMovement.DesiredGap,
		options.DefenderMovement.DesiredGap
	)
	-- EncounterPoint 是相遇中心，因此把期望边缘间距拆到中心两侧；
	-- 位置由统一的有向包围盒几何计算，不能用模型 X/Z 尺寸近似。
	local sideGap = desiredGap * 0.5
	local attackerPose = MonsterCombatGeometry.ResolvePoseToPoint(
		attackerModel,
		options.EncounterCFrame,
		sideGap,
		-direction
	)
	local defenderPose = MonsterCombatGeometry.ResolvePoseToPoint(
		defenderModel,
		options.EncounterCFrame,
		sideGap,
		direction
	)
	local attackerTarget = attackerPose.Position
	local defenderTarget = defenderPose.Position

	local function setMoving(model: Model, isMoving: boolean, moveSpeed: number?)
		if options.SetMoving then
			options.SetMoving(model, isMoving, moveSpeed)
		end
	end

	local function stopReason(): string?
		if options.IsCancelled and options.IsCancelled() then
			return "Cancelled"
		end
		local latestAttacker = MonsterRosterCoordinator.Get(
			attacker.Player,
			attacker.SpawnPointId
		)
		if not latestAttacker
			or not latestAttacker.Model
			or latestAttacker.State == "Defeated"
			or latestAttacker.State == "Recovering" then
			return "AttackerDefeated"
		end
		local latestDefender = MonsterRosterCoordinator.Get(
			defender.Player,
			defender.SpawnPointId
		)
		if not latestDefender
			or not latestDefender.Model
			or latestDefender.State == "Defeated"
			or latestDefender.State == "Recovering" then
			return "DefenderUnavailable"
		end
		return nil
	end

	local function move(
		model: Model,
		target: Vector3,
		movement: MovementConfig
	): (boolean, string?)
		local succeeded, moved = pcall(
			GodzillaMoveService.MoveTo,
			model,
			target,
			{
				MoveSpeed = movement.MoveSpeed,
				MaxTravelDuration = movement.MaxTravelDuration,
				TimingSafetyMargin = movement.TimingSafetyMargin,
				TurnDuration = movement.TurnDuration,
				SetMoving = function(isMoving, moveSpeed)
					setMoving(model, isMoving, moveSpeed)
				end,
			}
		)
		if not succeeded then
			return false, "EncounterMovementFailed"
		end
		return moved, if moved then nil else "EncounterMovementFailed"
	end

	local remaining = 2
	local movementResults: { [string]: { Succeeded: boolean, Reason: string? } } = {}
	local function runMovement(
		key: string,
		model: Model,
		target: Vector3,
		movement: MovementConfig
	)
		local succeeded, reason = move(model, target, movement)
		movementResults[key] = { Succeeded = succeeded, Reason = reason }
		remaining -= 1
	end

	task.spawn(runMovement, "Attacker", attackerModel, attackerTarget, options.AttackerMovement)
	task.spawn(runMovement, "Defender", defenderModel, defenderTarget, options.DefenderMovement)

	local cancelled = false
	while remaining > 0 do
		local reason = stopReason()
		if reason and not cancelled then
			cancelled = true
			GodzillaMoveService.Cancel(attackerModel)
			GodzillaMoveService.Cancel(defenderModel)
		end
		task.wait()
	end

	if cancelled then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, stopReason() or "EncounterCancelled")
	end
	if not movementResults.Attacker.Succeeded then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, movementResults.Attacker.Reason or "AttackerEncounterMovementFailed")
	end
	if not movementResults.Defender.Succeeded then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, movementResults.Defender.Reason or "DefenderEncounterMovementFailed")
	end

	local movementStopReason = stopReason()
	if movementStopReason then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, movementStopReason)
	end

	-- 两侧站位解决的是相遇中心；最终战斗间距必须继续复用战斗几何的
	-- ResolvePose，确保模型真实 Bounds/Pivot 偏移不会把双方推到 MaxGap 外。
	local latestAttacker = MonsterRosterCoordinator.Get(
		attacker.Player,
		attacker.SpawnPointId
	)
	local latestDefender = MonsterRosterCoordinator.Get(
		defender.Player,
		defender.SpawnPointId
	)
	if not latestAttacker
		or not latestAttacker.Model
		or not latestDefender
		or not latestDefender.Model
	then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, "EncounterCombatantUnavailable")
	end
	local attackerAlignedFacing = GodzillaMoveService.FaceTo(
		latestAttacker.Model,
		latestDefender.Model:GetPivot().Position,
		options.AttackerMovement.TurnDuration
	)
	if not attackerAlignedFacing then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, "EncounterCombatAlignmentFacingFailed")
	end
	local finalDefenderPose = MonsterCombatGeometry.ResolvePose(
		latestDefender.Model,
		latestAttacker.Model,
		desiredGap
	)
	local defenderAligned, defenderAlignReason = move(
		latestDefender.Model,
		finalDefenderPose.Position,
		options.DefenderMovement
	)
	if not defenderAligned then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, defenderAlignReason or "EncounterCombatAlignmentFailed")
	end
	local alignmentStopReason = stopReason()
	if alignmentStopReason then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, alignmentStopReason)
	end

	latestAttacker = MonsterRosterCoordinator.Get(
		attacker.Player,
		attacker.SpawnPointId
	)
	latestDefender = MonsterRosterCoordinator.Get(
		defender.Player,
		defender.SpawnPointId
	)
	if not latestAttacker
		or not latestAttacker.Model
		or not latestDefender
		or not latestDefender.Model
	then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, "EncounterCombatantUnavailable")
	end

	local attackerFaced = GodzillaMoveService.FaceTo(
		latestAttacker.Model,
		latestDefender.Model:GetPivot().Position,
		options.AttackerMovement.TurnDuration
	)
	local defenderFaced = GodzillaMoveService.FaceTo(
		latestDefender.Model,
		latestAttacker.Model:GetPivot().Position,
		options.DefenderMovement.TurnDuration
	)
	if not attackerFaced or not defenderFaced then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, "EncounterFacingFailed")
	end

	local finalGap = MonsterCombatGeometry.GetGap(
		latestAttacker.Model,
		latestDefender.Model
	)
	local maxAllowedGap = math.min(
		options.AttackerMovement.MaxGap,
		options.DefenderMovement.MaxGap
	)
	if finalGap > maxAllowedGap then
		restoreState(attacker, attackerState)
		restoreState(defender, defenderState)
		return result(false, "EncounterCombatPositionOutOfRange")
	end

	return result(true, nil)
end

return MonsterEncounterCoordinator
