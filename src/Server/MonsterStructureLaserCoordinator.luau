--[[
	职责：在守卫清空后，从固定落点向指定区域房屋逐栋发射激光并消耗一次出征伤害预算。
	输入：防守玩家、运行时怪兽、落点、区域、房屋访问器、动画/伤害配置和停止查询。
	输出：摧毁列表、奖励、实际建筑伤害和剩余预算。
	内部算法：按落点距离稳定选房 → 首栋蓄力并保持激光 → 发射中平滑转向 → 对准后提交预算伤害。
	不负责：移动到区域、守卫怪兽战斗、塔防、回城、恢复或决定出征总时限。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ContinuousAtomicLaserPresentation = require(
	script.Parent.ContinuousAtomicLaserPresentation
)
local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local HouseAttackActivityService = require(script.Parent.HouseAttackActivityService)
local HouseAttackCommitter = require(script.Parent.HouseAttackCommitter)
local HouseAttackTargetAccess = require(script.Parent.HouseAttackTargetAccess)
local HouseTargetReservationService = require(script.Parent.HouseTargetReservationService)
local RegionHouseTargetSelector = require(script.Parent.RegionHouseTargetSelector)
local StructureDamageBudgetRules = require(
	ReplicatedStorage.Shared.Building.StructureDamageBudgetRules
)
local ValueValidation = require(ReplicatedStorage.Shared.ValueValidation)

local MonsterStructureLaserCoordinator = {}

export type ModelAnimationConfig = {
	Animations: { [string]: number },
	AttackEffects: { [string]: string },
}

export type StructureAttackConfig = {
	StructureDamage: number,
	Animation: {
		HitProgress: number,
		Speed: number,
	},
}

export type ExecuteOptions = {
	TargetRegionId: string,
	HouseAccess: HouseAttackTargetAccess.Access,
	ModelAnimationConfig: ModelAnimationConfig,
	MonsterAttackConfig: StructureAttackConfig,
	TurnDuration: number,
	RewardAmount: number,
	RewardPlayer: Player,
	PollStopReason: (() -> string?)?,
	OnHouseDestroyed: ((string, HouseAttackCommitter.CommitResult) -> ())?,
}

export type CommandResult = {
	Succeeded: boolean,
	Reason: string?,
	ReachedDestination: boolean,
	DestroyedHouseIds: { string },
	RewardGranted: number,
	DamageApplied: number,
	RemainingDamage: number,
}

local function makeResult(
	succeeded: boolean,
	reason: string?,
	destroyedHouseIds: { string },
	rewardGranted: number,
	damageApplied: number,
	remainingDamage: number
): CommandResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		ReachedDestination = true,
		DestroyedHouseIds = table.clone(destroyedHouseIds),
		RewardGranted = rewardGranted,
		DamageApplied = damageApplied,
		RemainingDamage = remainingDamage,
	}
end

function MonsterStructureLaserCoordinator.Execute(
	defender: Player,
	monster: Model,
	entryPoint: Vector3,
	options: ExecuteOptions
): CommandResult
	assert(defender:IsA("Player"), "defender 必须是 Player")
	assert(monster:IsA("Model"), "monster 必须是 Model")
	assert(ValueValidation.IsFiniteVector3(entryPoint), "entryPoint 必须是有限 Vector3")
	assert(type(options) == "table", "options 必须是 table")
	assert(
		type(options.TargetRegionId) == "string" and options.TargetRegionId ~= "",
		"TargetRegionId 必须是非空字符串"
	)
	assert(type(options.HouseAccess) == "table", "HouseAccess 必须是 table")
	assert(type(options.ModelAnimationConfig) == "table", "ModelAnimationConfig 必须是 table")
	assert(type(options.MonsterAttackConfig) == "table", "MonsterAttackConfig 必须是 table")
	assert(
		ValueValidation.IsFiniteNumber(options.MonsterAttackConfig.StructureDamage)
			and options.MonsterAttackConfig.StructureDamage > 0,
		"StructureDamage 必须是有限正数"
	)
	assert(
		ValueValidation.IsFiniteNumber(options.TurnDuration) and options.TurnDuration > 0,
		"TurnDuration 必须是有限正数"
	)
	assert(
		ValueValidation.IsFiniteNumber(options.RewardAmount) and options.RewardAmount >= 0,
		"RewardAmount 必须是有限非负数"
	)
	assert(options.RewardPlayer:IsA("Player"), "RewardPlayer 必须是 Player")
	assert(
		options.PollStopReason == nil or type(options.PollStopReason) == "function",
		"PollStopReason 必须是 function 或 nil"
	)

	local atomicAssetId = options.ModelAnimationConfig.Animations.AtomicAttack
	local atomicEffectName = options.ModelAnimationConfig.AttackEffects.AtomicAttack
	if type(atomicAssetId) ~= "number" or atomicAssetId <= 0 then
		return makeResult(
			false,
			"AtomicAttackAnimationUnavailable",
			{},
			0,
			0,
			options.MonsterAttackConfig.StructureDamage
		)
	end
	if type(atomicEffectName) ~= "string" or atomicEffectName == "" then
		return makeResult(
			false,
			"AtomicAttackEffectUnavailable",
			{},
			0,
			0,
			options.MonsterAttackConfig.StructureDamage
		)
	end

	local remainingDamage = options.MonsterAttackConfig.StructureDamage
	local totalDamageApplied = 0
	local rewardGranted = 0
	local destroyedHouseIds = {}
	local ignoredHouseIds = {}
	local ownedReservation = nil
	local laserSession: ContinuousAtomicLaserPresentation.Session? = nil
	local currentBeamTargetPosition: Vector3? = nil

	local function releaseReservation()
		if ownedReservation then
			HouseTargetReservationService.Release(ownedReservation)
			ownedReservation = nil
		end
	end

	local function finish(succeeded: boolean, reason: string?): CommandResult
		releaseReservation()
		HouseAttackActivityService.End(monster)
		if laserSession then
			laserSession.Stop()
			laserSession = nil
		end
		return makeResult(
			succeeded,
			reason,
			destroyedHouseIds,
			rewardGranted,
			totalDamageApplied,
			remainingDamage
		)
	end

	local function pollStopReason(): string?
		if not monster:IsDescendantOf(workspace) then
			return "AttackerUnavailable"
		end
		if not options.PollStopReason then
			return nil
		end
		local succeeded, reason = pcall(options.PollStopReason)
		if not succeeded then
			error(reason, 0)
		end
		return reason
	end

	local function faceTargetWhileFiring(targetPosition: Vector3): (boolean, string?)
		if not laserSession or not currentBeamTargetPosition then
			local faced = GodzillaMoveService.FaceTo(
				monster,
				targetPosition,
				options.TurnDuration
			)
			return faced, if faced then nil else pollStopReason() or "FaceHouseFailed"
		end

		local sweepActive = true
		local sweepStopReason: string? = nil
		local sweepError: any? = nil
		local sweepStart = workspace:GetServerTimeNow()
		local startPosition = currentBeamTargetPosition
		task.spawn(function()
			while sweepActive do
				local succeeded, stopReason = pcall(pollStopReason)
				if not succeeded then
					sweepError = stopReason
					GodzillaMoveService.Cancel(monster)
					break
				end
				if stopReason then
					sweepStopReason = stopReason
					GodzillaMoveService.Cancel(monster)
					break
				end
				local alpha = math.clamp(
					(workspace:GetServerTimeNow() - sweepStart) / options.TurnDuration,
					0,
					1
				)
				laserSession.UpdateTarget(startPosition:Lerp(targetPosition, alpha))
				RunService.Heartbeat:Wait()
			end
		end)
		local faced = GodzillaMoveService.FaceTo(
			monster,
			targetPosition,
			options.TurnDuration
		)
		sweepActive = false
		if sweepError ~= nil then
			error(sweepError, 0)
		end
		if sweepStopReason then
			return false, sweepStopReason
		end
		if not faced then
			return false, pollStopReason() or "FaceHouseFailed"
		end
		laserSession.UpdateTarget(targetPosition)
		currentBeamTargetPosition = targetPosition
		return true, nil
	end

	while remainingDamage > 0 do
		local stopReason = pollStopReason()
		if stopReason then
			return finish(false, stopReason)
		end

		local candidate = RegionHouseTargetSelector.Select(
			entryPoint,
			options.TargetRegionId,
			options.HouseAccess.ListAliveTargets(defender),
			ignoredHouseIds
		)
		if not candidate then
			return finish(true, nil)
		end

		local latestTarget = options.HouseAccess.ResolveAliveTarget(
			defender,
			candidate.HouseId
		)
		if not latestTarget or latestTarget.RegionId ~= options.TargetRegionId then
			ignoredHouseIds[candidate.HouseId] = true
			continue
		end
		local allocation = StructureDamageBudgetRules.Allocate(
			remainingDamage,
			latestTarget.CurrentHealth
		)
		if allocation.DamageToApply <= 0 then
			return finish(true, nil)
		end

		ownedReservation = HouseTargetReservationService.TryAcquire(
			defender,
			latestTarget.HouseId,
			monster,
			latestTarget.HealthGeneration
		)
		if not ownedReservation then
			ignoredHouseIds[latestTarget.HouseId] = true
			continue
		end
		HouseAttackActivityService.Begin(monster, defender, latestTarget.HouseId)

		local targetPosition = latestTarget.CFrame.Position
		local faced, faceReason = faceTargetWhileFiring(targetPosition)
		if not faced then
			return finish(false, faceReason or "FaceHouseFailed")
		end

		if not laserSession then
			local started, sessionOrError, startReason = pcall(
				ContinuousAtomicLaserPresentation.Start,
				monster,
				atomicAssetId,
				atomicEffectName,
				targetPosition,
				{
					HoldProgress = options.MonsterAttackConfig.Animation.HitProgress,
					Speed = options.MonsterAttackConfig.Animation.Speed,
					IsCancelled = function()
						return pollStopReason() ~= nil
					end,
				}
			)
			if not started then
				warn("持续激光启动失败：", sessionOrError)
				return finish(false, "AttackAnimationFailed")
			end
			if not sessionOrError then
				return finish(false, startReason or pollStopReason() or "AttackInterrupted")
			end
			laserSession = sessionOrError
			currentBeamTargetPosition = targetPosition
		end

		local committed, commitResultOrError = pcall(
			HouseAttackCommitter.Commit,
			ownedReservation,
			options.HouseAccess,
			{
				MaxGap = 0,
				EnforceRange = false,
				Damage = allocation.DamageToApply,
				RewardAmount = options.RewardAmount,
				RewardPlayer = options.RewardPlayer,
			}
		)
		HouseAttackActivityService.End(monster)
		if not committed then
			warn("持续激光伤害提交失败：", commitResultOrError)
			return finish(false, "HouseAttackCommitFailed")
		end
		ownedReservation = nil
		local commitResult = commitResultOrError
		if not commitResult or not commitResult.Succeeded then
			releaseReservation()
			ignoredHouseIds[latestTarget.HouseId] = true
			continue
		end
		remainingDamage = math.max(0, remainingDamage - commitResult.DamageApplied)
		totalDamageApplied += commitResult.DamageApplied
		if commitResult.Destroyed then
			table.insert(destroyedHouseIds, commitResult.HouseId)
			rewardGranted += commitResult.RewardGranted
			HouseAttackActivityService.EndHouse(defender, commitResult.HouseId)
			if options.OnHouseDestroyed then
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
	end

	return finish(true, nil)
end

return MonsterStructureLaserCoordinator
