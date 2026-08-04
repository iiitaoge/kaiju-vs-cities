local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackAnimationPlayer = require(script.Parent.AttackAnimationPlayer)
local AttackAnimationSelector = require(script.Parent.AttackAnimationSelector)
local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local GodzillaService = require(script.Parent.GodzillaService)
local HouseAttackCommitter = require(script.Parent.HouseAttackCommitter)
local HouseAttackGeometry = require(script.Parent.HouseAttackGeometry)
local HouseAttackTargetAccess = require(script.Parent.HouseAttackTargetAccess)
local NearbyHouseTargetSelector = require(script.Parent.NearbyHouseTargetSelector)
local HouseTargetReservationService = require(script.Parent.HouseTargetReservationService)
local MonsterMovementRules = require(
	ReplicatedStorage.Shared.Monster.MonsterMovementRules
)
local ValueValidation = require(ReplicatedStorage.Shared.ValueValidation)

local MonsterAttackCoordinator = {}

local DETECTION_INTERVAL = 0.1

export type ModelAnimationConfig = {
	Animations: { [string]: number },
	AttackSequence: { string },
}

export type MonsterAttackConfig = {
	StructureDamage: number,
	Detection: {
		Radius: number,
		MovementLookAheadSeconds: number?,
	},
	Geometry: {
		DesiredGap: number,
		MaxGap: number,
	},
	Animation: {
		SelectionMode: AttackAnimationSelector.SelectionMode,
		HitProgress: number,
		Speed: number,
	},
}

export type ExecuteOptions = {
	HouseAccess: HouseAttackTargetAccess.Access,
	ModelAnimationConfig: ModelAnimationConfig,
	MonsterAttackConfig: MonsterAttackConfig,
	MoveSpeed: number,
	MaxTravelDuration: number?,
	TimingSafetyMargin: number?,
	TurnDuration: number,
	WalkAnimation: any?,
	RewardAmount: number,
	RewardPlayer: Player,
	-- 移动或攻击期间轮询外部防御事件；nil 表示当前没有中断。
	PollInterruption: (() -> any?)?,
	-- 处理中断并决定是否继续原来的房屋攻击路线。
	HandleInterruption: ((any) -> { Continue: boolean, Reason: string? })?,
	-- 房屋攻击链路进入移动或攻击阶段时通知上层状态协调器。
	OnPhaseChanged: (("MovingToTarget" | "AttackingStructure") -> ())?,
	-- 成功提交摧毁后调用；表现或网络通知由调用者注入。
	OnHouseDestroyed: ((string, HouseAttackCommitter.CommitResult) -> ())?,
}

export type CommandResult = {
	Succeeded: boolean,
	Reason: string?,
	ReachedDestination: boolean,
	-- 本条目标点命令中按实际成功顺序摧毁的全部房屋。
	DestroyedHouseIds: { string },
	-- 本条命令累计获得的奖励。
	RewardGranted: number,
}

local latestCommandIds: { [Model]: number } = setmetatable({}, { __mode = "k" })
local activeReservations: {
	[Model]: HouseTargetReservationService.Reservation,
} = setmetatable({}, { __mode = "k" })

local function makeResult(
	succeeded: boolean,
	reason: string?,
	reachedDestination: boolean,
	destroyedHouseIds: { string },
	rewardGranted: number
): CommandResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		ReachedDestination = reachedDestination,
		DestroyedHouseIds = table.clone(destroyedHouseIds),
		RewardGranted = rewardGranted,
	}
end

local function releaseCurrentReservation(model: Model)
	local reservation = activeReservations[model]
	if reservation then
		HouseTargetReservationService.Release(reservation)
		if activeReservations[model] == reservation then
			activeReservations[model] = nil
		end
	end
end

-- 输入：
--   defender：被攻击房屋状态所属玩家。
--   monster：已在 Workspace 的怪兽模型。
--   destination：最终点击坐标；移动只使用 X/Z。
--   options：显式注入房屋数据源、两类配置、移动参数、奖励和可选成功回调。
-- 输出：
--   返回命令是否正常到达最终点、失败原因、本次摧毁房屋和累计奖励。
--   命令取消或失败前已经成功结算的房屋仍包含在输出中。
-- 内部算法：
--   先朝最终点移动，移动期间每 0.1 秒查询怪兽检测半径内的最新房屋；
--   发现目标后中断原移动并预约，计算站位、转向，在动画命中进度重新提交。
--   每次只攻击一栋；成功后重新查询当前半径，附近清空后再恢复原目标移动，
--   直到沿途可攻击房屋处理完毕并到达最终点。候选失效时忽略并恢复原移动。
--   同一怪兽的新命令会取消旧命令；旧命令只清理自己持有的预约和动画。
-- 副作用：
--   移动怪兽、切换移动/攻击动画，并通过注入的数据源提交一次房屋摧毁和奖励。
--   不创建怪兽、不监听 RemoteEvent、不直接播放客户端摧毁表现。
function MonsterAttackCoordinator.Execute(
	defender: Player,
	monster: Model,
	destination: Vector3,
	options: ExecuteOptions
): CommandResult
	assert(defender:IsA("Player"), "defender 必须是 Player")
	assert(monster:IsA("Model"), "monster 必须是 Model")
	assert(
		ValueValidation.IsFiniteVector3(destination),
		"destination 必须是有限 Vector3"
	)
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.HouseAccess) == "table", "HouseAccess 必须是 table")
	assert(type(options.ModelAnimationConfig) == "table", "ModelAnimationConfig 必须是 table")
	assert(type(options.MonsterAttackConfig) == "table", "MonsterAttackConfig 必须是 table")
	assert(
		type(options.MonsterAttackConfig.StructureDamage) == "number"
			and options.MonsterAttackConfig.StructureDamage > 0,
		"StructureDamage 必须大于 0"
	)
	assert(type(options.MoveSpeed) == "number" and options.MoveSpeed > 0, "MoveSpeed 必须大于 0")
	assert(
		type(options.TurnDuration) == "number" and options.TurnDuration > 0,
		"TurnDuration 必须大于 0"
	)
	if options.MaxTravelDuration ~= nil then
		local safetyMargin = options.TimingSafetyMargin or 0
		assert(
			type(options.MaxTravelDuration) == "number"
				and type(safetyMargin) == "number"
				and safetyMargin >= 0
				and options.MaxTravelDuration > options.TurnDuration + safetyMargin,
			"MaxTravelDuration 必须大于 TurnDuration 与 TimingSafetyMargin 之和"
		)
	end
	MonsterMovementRules.ResolveWalkAnimationSpeed(
		options.MoveSpeed,
		options.WalkAnimation
	)
	MonsterMovementRules.ResolveDetectionRadius(
		options.MonsterAttackConfig.Detection.Radius,
		0,
		options.MonsterAttackConfig.Detection.MovementLookAheadSeconds
	)
	assert(
		type(options.RewardAmount) == "number" and options.RewardAmount >= 0,
		"RewardAmount 必须大于等于 0"
	)
	assert(
		typeof(options.RewardPlayer) == "Instance" and options.RewardPlayer:IsA("Player"),
		"RewardPlayer 必须是 Player"
	)
	assert(
		options.PollInterruption == nil or type(options.PollInterruption) == "function",
		"PollInterruption 必须是 function 或 nil"
	)
	assert(
		options.HandleInterruption == nil or type(options.HandleInterruption) == "function",
		"HandleInterruption 必须是 function 或 nil"
	)
	assert(
		options.OnPhaseChanged == nil or type(options.OnPhaseChanged) == "function",
		"OnPhaseChanged 必须是 function 或 nil"
	)

	releaseCurrentReservation(monster)
	local commandId = (latestCommandIds[monster] or 0) + 1
	latestCommandIds[monster] = commandId
	local ownedReservation: HouseTargetReservationService.Reservation? = nil

	local function isCurrent(): boolean
		return latestCommandIds[monster] == commandId and monster:IsDescendantOf(workspace)
	end

	local function releaseOwnedReservation()
		local reservation = ownedReservation
		if not reservation then
			return
		end

		HouseTargetReservationService.Release(reservation)
		if activeReservations[monster] == reservation then
			activeReservations[monster] = nil
		end
		ownedReservation = nil
	end

	local activeMoveSpeed = 0
	local function setMoving(isMoving: boolean, moveSpeed: number?)
		activeMoveSpeed = if isMoving then moveSpeed or options.MoveSpeed else 0
		if isCurrent() then
			GodzillaService.SetMoving(
				monster,
				options.ModelAnimationConfig,
				isMoving,
				moveSpeed,
				options.WalkAnimation
			)
		end
	end

	local function moveTo(position: Vector3): boolean
		if not isCurrent() then
			return false
		end
		return GodzillaMoveService.MoveTo(monster, position, {
			MoveSpeed = options.MoveSpeed,
			MaxTravelDuration = options.MaxTravelDuration,
			TimingSafetyMargin = options.TimingSafetyMargin,
			TurnDuration = options.TurnDuration,
			SetMoving = setMoving,
		})
	end

	local function pollInterruption()
		if not options.PollInterruption then
			return nil
		end
		local succeeded, value = pcall(options.PollInterruption)
		if not succeeded then
			error(value, 0)
		end
		return value
	end

	local function handleInterruption(value): (boolean, string?)
		GodzillaMoveService.Cancel(monster)
		setMoving(false, nil)
		if not options.HandleInterruption then
			return false, "Interrupted"
		end
		local succeeded, result = pcall(options.HandleInterruption, value)
		if not succeeded then
			error(result, 0)
		end
		if type(result) ~= "table" or type(result.Continue) ~= "boolean" then
			return false, "InvalidInterruptionResult"
		end
		return result.Continue, result.Reason
	end

	local function notifyPhase(phase: "MovingToTarget" | "AttackingStructure")
		if not options.OnPhaseChanged then
			return
		end
		local succeeded, callbackError = pcall(options.OnPhaseChanged, phase)
		if not succeeded then
			error(callbackError, 0)
		end
	end

	local ignoredHouseIds = {}
	local destroyedHouseIds = {}
	local rewardGranted = 0

	local function selectCurrentTarget(): NearbyHouseTargetSelector.HouseCandidate?
		local candidates = {}
		for _, candidate in options.HouseAccess.ListAliveTargets(defender) do
			if not ignoredHouseIds[candidate.HouseId] then
				table.insert(candidates, candidate)
			end
		end

		local detection = options.MonsterAttackConfig.Detection
		return NearbyHouseTargetSelector.Select(
			monster,
			candidates,
			{
				Radius = MonsterMovementRules.ResolveDetectionRadius(
					detection.Radius,
					activeMoveSpeed,
					detection.MovementLookAheadSeconds
				),
			}
		)
	end

	-- 输入：当前命令的 monster、destination 和半径查询闭包。
	-- 输出：
	--   reachedDestination 表示移动是否完整到达最终点；
	--   candidate 表示移动途中进入半径的第一栋房屋；
	--   reason 只在移动失败或命令取消时返回。
	-- 内部算法：
	--   移动在独立任务执行，当前协程每 0.1 秒读取怪兽最新位置并查询半径。
	--   找到候选后立即返回；随后攻击站位移动会取消仍在执行的原目标移动。
	local function moveUntilTarget(): (
		boolean,
		NearbyHouseTargetSelector.HouseCandidate?,
		string?,
		any?
	)
		local initialInterruption = pollInterruption()
		if initialInterruption ~= nil then
			return false, nil, nil, initialInterruption
		end
		-- 攻击结束后先清理当前位置半径，不让怪兽在附近房屋之间反复起步。
		local currentCandidate = selectCurrentTarget()
		if currentCandidate then
			return false, currentCandidate, nil, nil
		end

		local pivotPosition = monster:GetPivot().Position
		local horizontalOffset = Vector2.new(
			destination.X - pivotPosition.X,
			destination.Z - pivotPosition.Z
		)
		if horizontalOffset.Magnitude <= 0.01 then
			return true, nil, nil, nil
		end

		local moveFinished = false
		local moveCompleted = false
		local moveFailure = nil

		task.spawn(function()
			local succeeded, result = pcall(moveTo, destination)
			if succeeded then
				moveCompleted = result
			else
				moveFailure = tostring(result)
			end
			moveFinished = true
		end)

		while isCurrent() and not moveFinished do
			local interruption = pollInterruption()
			if interruption ~= nil then
				return false, nil, nil, interruption
			end
			local candidate = selectCurrentTarget()
			if candidate then
				return false, candidate, nil, nil
			end
			task.wait(DETECTION_INTERVAL)
		end

		if not isCurrent() then
			return false, nil, "Cancelled", nil
		end

		-- 到达的同一时刻也要检查一次，避免遗漏刚进入半径的房屋。
		local candidate = selectCurrentTarget()
		if candidate then
			return false, candidate, nil, nil
		end
		if moveFailure then
			warn("移动到最终点失败：", moveFailure)
			return false, nil, "MoveToDestinationFailed", nil
		end
		if not moveCompleted then
			return false, nil, "MoveToDestinationFailed", nil
		end

		return true, nil, nil, nil
	end

	while isCurrent() do
		notifyPhase("MovingToTarget")
		local reachedDestination, candidate, moveReason, interruption = moveUntilTarget()
		if interruption ~= nil then
			local shouldContinue, interruptionReason = handleInterruption(interruption)
			if shouldContinue then
				continue
			end
			return makeResult(
				false,
				interruptionReason or "Interrupted",
				false,
				destroyedHouseIds,
				rewardGranted
			)
		end
		if not candidate then
			if reachedDestination then
				return makeResult(
					true,
					nil,
					true,
					destroyedHouseIds,
					rewardGranted
				)
			end
			return makeResult(
				false,
				moveReason or "MoveToDestinationFailed",
				false,
				destroyedHouseIds,
				rewardGranted
			)
		end
		if not isCurrent() then
			return makeResult(
				false,
				"Cancelled",
				false,
				destroyedHouseIds,
				rewardGranted
			)
		end

		local latestTarget = options.HouseAccess.ResolveAliveTarget(
			defender,
			candidate.HouseId
		)
		if not latestTarget then
			releaseOwnedReservation()
			ignoredHouseIds[candidate.HouseId] = true
			continue
		end

		local reservation = HouseTargetReservationService.TryAcquire(
			defender,
			candidate.HouseId,
			monster,
			latestTarget.HealthGeneration
		)
		if not reservation then
			ignoredHouseIds[candidate.HouseId] = true
			continue
		end
		ownedReservation = reservation
		activeReservations[monster] = reservation

		local pose = HouseAttackGeometry.ResolvePose(
			monster,
			latestTarget,
			options.MonsterAttackConfig.Geometry.DesiredGap
		)
		notifyPhase("AttackingStructure")
		local movedToAttackPosition = moveTo(pose.Position)
		if not movedToAttackPosition then
			releaseOwnedReservation()
			return makeResult(
				false,
				if isCurrent() then "MoveToAttackPositionFailed" else "Cancelled",
				false,
				destroyedHouseIds,
				rewardGranted
			)
		end
		if not isCurrent() then
			releaseOwnedReservation()
			return makeResult(
				false,
				"Cancelled",
				false,
				destroyedHouseIds,
				rewardGranted
			)
		end

		local faced = GodzillaMoveService.FaceTo(
			monster,
			pose.LookAtPosition,
			options.TurnDuration
		)
		if not faced then
			releaseOwnedReservation()
			return makeResult(
				false,
				if isCurrent() then "FaceHouseFailed" else "Cancelled",
				false,
				destroyedHouseIds,
				rewardGranted
			)
		end

		local choice = AttackAnimationSelector.Next(
			monster,
			options.ModelAnimationConfig.Animations,
			options.ModelAnimationConfig.AttackSequence,
			{
				Mode = options.MonsterAttackConfig.Animation.SelectionMode,
			}
		)
		local commitResult: HouseAttackCommitter.CommitResult? = nil
		local pendingInterruption = nil
		local animationSucceeded, playbackOrError = pcall(
			AttackAnimationPlayer.Play,
			monster,
			choice.AssetId,
			{
				HitProgress = options.MonsterAttackConfig.Animation.HitProgress,
				Speed = options.MonsterAttackConfig.Animation.Speed,
				Priority = Enum.AnimationPriority.Action,
				IsCancelled = function()
					if not isCurrent() then
						return true
					end
					pendingInterruption = pollInterruption()
					return pendingInterruption ~= nil
				end,
			},
			function()
				if not isCurrent() then
					releaseOwnedReservation()
					return
				end

				commitResult = HouseAttackCommitter.Commit(
					reservation,
					options.HouseAccess,
					{
						MaxGap = options.MonsterAttackConfig.Geometry.MaxGap,
						Damage = options.MonsterAttackConfig.StructureDamage,
						RewardAmount = options.RewardAmount,
						RewardPlayer = options.RewardPlayer,
					}
				)
				if activeReservations[monster] == reservation then
					activeReservations[monster] = nil
				end
				if ownedReservation == reservation then
					ownedReservation = nil
				end

				if commitResult.Succeeded
					and commitResult.Destroyed
					and options.OnHouseDestroyed then
					local callbackSucceeded, callbackError = pcall(
						options.OnHouseDestroyed,
						commitResult.HouseId,
						commitResult
					)
					if not callbackSucceeded then
						warn("OnHouseDestroyed 回调失败：", callbackError)
					end
				end
			end
		)

		if not animationSucceeded then
			releaseOwnedReservation()
			warn("攻击动画播放失败：", playbackOrError)
			return makeResult(
				false,
				"AttackAnimationFailed",
				false,
				destroyedHouseIds,
				rewardGranted
			)
		end
		local playback = playbackOrError

		-- 命中后即使马上被新命令取消，已经发生的状态和奖励也必须出现在旧命令输出中。
		if commitResult and commitResult.Succeeded and commitResult.Destroyed then
			table.insert(destroyedHouseIds, commitResult.HouseId)
			rewardGranted += commitResult.RewardGranted
		end

		if pendingInterruption ~= nil then
			releaseOwnedReservation()
			local shouldContinue, interruptionReason = handleInterruption(pendingInterruption)
			if shouldContinue then
				continue
			end
			return makeResult(
				false,
				interruptionReason or "Interrupted",
				false,
				destroyedHouseIds,
				rewardGranted
			)
		end

		if playback.Cancelled or not isCurrent() then
			releaseOwnedReservation()
			return makeResult(
				false,
				"Cancelled",
				false,
				destroyedHouseIds,
				rewardGranted
			)
		end
		if not playback.HitTriggered then
			releaseOwnedReservation()
			return makeResult(
				false,
				"AttackInterrupted",
				false,
				destroyedHouseIds,
				rewardGranted
			)
		end

		if not commitResult or not commitResult.Succeeded then
			releaseOwnedReservation()
			ignoredHouseIds[candidate.HouseId] = true
		end
	end

	releaseOwnedReservation()
	return makeResult(
		false,
		"Cancelled",
		false,
		destroyedHouseIds,
		rewardGranted
	)
end

return MonsterAttackCoordinator
