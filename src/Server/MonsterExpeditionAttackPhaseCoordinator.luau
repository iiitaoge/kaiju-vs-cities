--[[
	职责：编排一次出征从目标落点、区域守卫到建筑激光的攻击阶段。
	输入：防守玩家、进攻怪兽、落点，以及移动、守卫中断、区域和建筑攻击依赖。
	输出：与建筑攻击命令兼容的结果；到达落点后，守卫必须逐只处理完才能进入激光阶段。
	内部算法：移动到固定落点 → 循环 Poll/Handle 守卫事件 → 区域持续激光伤害预算。
	不负责：决定怪兽战斗胜负、恢复、回城、塔伤害或存档。
]]

local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local GodzillaService = require(script.Parent.GodzillaService)
local HouseAttackCommitter = require(script.Parent.HouseAttackCommitter)
local HouseAttackTargetAccess = require(script.Parent.HouseAttackTargetAccess)
local MonsterAttackCoordinator = require(script.Parent.MonsterAttackCoordinator)
local MonsterStructureLaserCoordinator = require(
	script.Parent.MonsterStructureLaserCoordinator
)

local MonsterExpeditionAttackPhaseCoordinator = {}

export type ExecuteOptions = {
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
	RewardPlayer: Player,
	PollStopReason: (() -> string?)?,
	PollInterruption: (() -> any?)?,
	HandleInterruption: ((any) -> { Continue: boolean, Reason: string? })?,
	OnPhaseChanged: (("MovingToTarget" | "AttackingStructure") -> ())?,
	OnHouseDestroyed: ((string, HouseAttackCommitter.CommitResult) -> ())?,
}

local function makeResult(
	succeeded: boolean,
	reason: string?,
	reachedDestination: boolean
)
	return {
		Succeeded = succeeded,
		Reason = reason,
		ReachedDestination = reachedDestination,
		DestroyedHouseIds = {},
		RewardGranted = 0,
		DamageApplied = 0,
		RemainingDamage = 0,
	}
end

function MonsterExpeditionAttackPhaseCoordinator.Execute(
	defender: Player,
	monster: Model,
	destination: Vector3,
	options: ExecuteOptions
)
	assert(defender:IsA("Player"), "defender 必须是 Player")
	assert(monster:IsA("Model"), "monster 必须是 Model")
	assert(type(options) == "table", "options 必须是 table")
	assert(
		type(options.TargetRegionId) == "string" and options.TargetRegionId ~= "",
		"TargetRegionId 无效"
	)
	assert(
		options.PollInterruption == nil or type(options.PollInterruption) == "function",
		"PollInterruption 无效"
	)
	assert(
		options.HandleInterruption == nil or type(options.HandleInterruption) == "function",
		"HandleInterruption 无效"
	)

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

	local stopReason = pollStopReason()
	if stopReason then
		return makeResult(false, stopReason, false)
	end
	if options.OnPhaseChanged then
		options.OnPhaseChanged("MovingToTarget")
	end
	local moveActive = true
	local moveStopReason: string? = nil
	local movePollError: any? = nil
	task.spawn(function()
		while moveActive do
			local succeeded, reason = pcall(pollStopReason)
			if not succeeded then
				movePollError = reason
				GodzillaMoveService.Cancel(monster)
				break
			end
			if reason then
				moveStopReason = reason
				GodzillaMoveService.Cancel(monster)
				break
			end
			task.wait(0.05)
		end
	end)
	local moved = GodzillaMoveService.MoveTo(monster, destination, {
		MoveSpeed = options.MoveSpeed,
		MaxTravelDuration = options.MaxTravelDuration,
		TimingSafetyMargin = options.TimingSafetyMargin,
		TurnDuration = options.TurnDuration,
		SetMoving = function(isMoving, moveSpeed)
			GodzillaService.SetMoving(
				monster,
				options.ModelAnimationConfig,
				isMoving,
				moveSpeed,
				options.WalkAnimation
			)
		end,
	})
	moveActive = false
	if movePollError ~= nil then
		error(movePollError, 0)
	end
	if moveStopReason then
		return makeResult(false, moveStopReason, false)
	end
	if not moved then
		return makeResult(
			false,
			moveStopReason or pollStopReason() or "MoveToDestinationFailed",
			false
		)
	end

	while options.PollInterruption do
		stopReason = pollStopReason()
		if stopReason then
			return makeResult(false, stopReason, true)
		end
		local pollSucceeded, event = pcall(options.PollInterruption)
		if not pollSucceeded then
			error(event, 0)
		end
		if event == nil then
			break
		end
		if not options.HandleInterruption then
			return makeResult(false, "UnhandledDefenseEvent", true)
		end
		local handled = options.HandleInterruption(event)
		if not handled.Continue then
			return makeResult(false, handled.Reason or "DefenseInterruptionFailed", true)
		end
	end

	stopReason = pollStopReason()
	if stopReason then
		return makeResult(false, stopReason, true)
	end
	if options.OnPhaseChanged then
		options.OnPhaseChanged("AttackingStructure")
	end
	return MonsterStructureLaserCoordinator.Execute(
		defender,
		monster,
		destination,
		{
			TargetRegionId = options.TargetRegionId,
			HouseAccess = options.HouseAccess,
			ModelAnimationConfig = options.ModelAnimationConfig,
			MonsterAttackConfig = options.MonsterAttackConfig,
			TurnDuration = options.TurnDuration,
			RewardAmount = options.RewardAmount,
			RewardPlayer = options.RewardPlayer,
			PollStopReason = pollStopReason,
			OnHouseDestroyed = options.OnHouseDestroyed,
		}
	)
end

return MonsterExpeditionAttackPhaseCoordinator
