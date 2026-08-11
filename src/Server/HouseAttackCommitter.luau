local GameAnalyticsGateway = require(script.Parent.Analytics.GameAnalyticsGateway)
local HouseAttackGeometry = require(script.Parent.HouseAttackGeometry)
local HouseAttackTargetAccess = require(script.Parent.HouseAttackTargetAccess)
local HouseTargetReservationService = require(script.Parent.HouseTargetReservationService)
local MoneyService = require(script.Parent.MoneyService)
local PlayerJourneyAnalyticsCoordinator = require(
	script.Parent.Analytics.PlayerJourneyAnalyticsCoordinator
)

local HouseAttackCommitter = {}

export type CommitOptions = {
	-- 允许怪兽与房屋水平包围盒之间存在的最大边缘距离。
	MaxGap: number,
	-- false 时跳过近战距离重验，供只有目标终点、没有射程限制的激光使用。
	EnforceRange: boolean?,
	-- 本次命中对建筑造成的伤害。
	Damage: number,
	-- 本次成功摧毁房屋应增加的金钱；没有隐藏默认值。
	RewardAmount: number,
	-- 本次成功摧毁房屋的进攻方奖励接收者。
	RewardPlayer: Player,
}

export type CommitResult = {
	-- 命中是否被服务器接受；普通非致命命中也为 true。
	Succeeded: boolean,
	Reason: string?,
	HouseId: string,
	Destroyed: boolean,
	StateChanged: boolean,
	DamageApplied: number,
	PreviousHealth: number?,
	RemainingHealth: number?,
	MaxHealth: number?,
	HealthGeneration: number?,
	RewardGranted: number,
	Balance: number?,
	ReservationReleased: boolean,
}

local function makeResult(
	houseId: string,
	succeeded: boolean,
	reason: string?,
	destroyed: boolean,
	damageResult: HouseAttackTargetAccess.DamageResult?,
	rewardGranted: number,
	balance: number?,
	reservationReleased: boolean
): CommitResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		HouseId = houseId,
		Destroyed = destroyed,
		StateChanged = destroyed,
		DamageApplied = if damageResult then damageResult.DamageApplied else 0,
		PreviousHealth = if damageResult then damageResult.PreviousHealth else nil,
		RemainingHealth = if damageResult then damageResult.CurrentHealth else nil,
		MaxHealth = if damageResult then damageResult.MaxHealth else nil,
		HealthGeneration = if damageResult then damageResult.Generation else nil,
		RewardGranted = rewardGranted,
		Balance = balance,
		ReservationReleased = reservationReleased,
	}
end

-- 输入：有效房屋凭证、显式攻击访问器、距离/伤害/奖励配置。
-- 输出：本次命中、剩余血量、是否摧毁及最后一击奖励。
-- 内部算法：重验凭证和代次 → 重验距离 → 原子扣血；非致命命中立即结束；
--   致命命中才提交 Destroyed 生命周期、作废同房屋全部集火凭证并奖励最后一击。
-- 副作用：可能扣除房屋会话血量、切换房屋生命周期、发放金钱并消费凭证。
function HouseAttackCommitter.Commit(
	reservation: HouseTargetReservationService.Reservation,
	access: HouseAttackTargetAccess.Access,
	options: CommitOptions
): CommitResult
	assert(type(access) == "table", "access 必须是 HouseAttackTargetAccess.Access")
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.MaxGap) == "number" and options.MaxGap >= 0, "MaxGap 必须大于等于 0")
	assert(
		options.EnforceRange == nil or type(options.EnforceRange) == "boolean",
		"EnforceRange 必须是 boolean 或 nil"
	)
	assert(
		type(options.Damage) == "number"
			and options.Damage == options.Damage
			and options.Damage < math.huge
			and options.Damage > 0,
		"Damage 必须是有限正数"
	)
	assert(
		type(options.RewardAmount) == "number" and options.RewardAmount >= 0,
		"RewardAmount 必须大于等于 0"
	)
	assert(
		typeof(options.RewardPlayer) == "Instance" and options.RewardPlayer:IsA("Player"),
		"RewardPlayer 必须是 Player"
	)

	local houseId = if type(reservation) == "table" and type(reservation.HouseId) == "string"
		then reservation.HouseId
		else ""
	if not HouseTargetReservationService.Validate(reservation) then
		return makeResult(houseId, false, "InvalidReservation", false, nil, 0, nil, false)
	end

	local function fail(
		reason: string,
		damageResult: HouseAttackTargetAccess.DamageResult?
	): CommitResult
		local released = HouseTargetReservationService.Release(reservation)
		return makeResult(houseId, false, reason, false, damageResult, 0, nil, released)
	end

	local target, resolveReason = access.ResolveAliveTarget(reservation.Defender, houseId)
	if not target then
		return fail(resolveReason or "HouseUnavailable", nil)
	end
	if target.HealthGeneration ~= reservation.HealthGeneration then
		return fail("StaleHealthGeneration", nil)
	end

	if options.EnforceRange ~= false then
		local gap = HouseAttackGeometry.GetGap(reservation.Monster, target)
		if gap > options.MaxGap then
			return fail("OutOfRange", nil)
		end
	end

	local damageResult = access.ApplyDamage(
		reservation.Defender,
		houseId,
		reservation.HealthGeneration,
		options.Damage
	)
	if not damageResult.Accepted then
		return fail(damageResult.Reason or "DamageRejected", damageResult)
	end
	if not damageResult.Depleted then
		local released = HouseTargetReservationService.Release(reservation)
		return makeResult(houseId, true, nil, false, damageResult, 0, nil, released)
	end

	local previousHealth = damageResult.PreviousHealth
	local generation = damageResult.Generation
	assert(previousHealth ~= nil and generation ~= nil, "致命伤害必须返回血量和代次")
	local prepared, prepareReason = access.PrepareDestroy(reservation.Defender, houseId)
	if not prepared then
		local rolledBack = access.RollbackDamage(
			reservation.Defender,
			houseId,
			generation,
			previousHealth
		)
		if not rolledBack then
			warn(string.format("建筑致命伤害准备失败且回滚失败：%s/%s", reservation.Defender.Name, houseId))
		end
		local reportedDamage = table.clone(damageResult)
		if rolledBack then
			reportedDamage.CurrentHealth = previousHealth
			reportedDamage.DamageApplied = 0
			reportedDamage.Depleted = false
		end
		return fail(prepareReason or "PrepareDestroyFailed", reportedDamage)
	end

	local destroyed, destroyReason = access.Destroy(reservation.Defender, houseId)
	if not destroyed then
		local rolledBack = access.RollbackDamage(
			reservation.Defender,
			houseId,
			generation,
			previousHealth
		)
		if not rolledBack then
			warn(string.format("建筑摧毁失败且伤害回滚失败：%s/%s", reservation.Defender.Name, houseId))
		end
		local reportedDamage = table.clone(damageResult)
		if rolledBack then
			reportedDamage.CurrentHealth = previousHealth
			reportedDamage.DamageApplied = 0
			reportedDamage.Depleted = false
		end
		return fail(destroyReason or "DestroyRejected", reportedDamage)
	end

	local balance = MoneyService.Earn(options.RewardPlayer, options.RewardAmount)
	if options.RewardAmount > 0 then
		PlayerJourneyAnalyticsCoordinator.RecordMoneyRunEarnings(options.RewardPlayer)
	end
	GameAnalyticsGateway.LogDesign(
		options.RewardPlayer,
		"Gameplay:Combat:HouseDestroyed:" .. houseId,
		options.RewardAmount
	)
	GameAnalyticsGateway.LogResource(
		options.RewardPlayer,
		"Source",
		options.RewardAmount,
		"Combat",
		"House-" .. houseId
	)
	local invalidated = HouseTargetReservationService.InvalidateHouse(
		reservation.Defender,
		houseId
	)
	return makeResult(
		houseId,
		true,
		nil,
		true,
		damageResult,
		options.RewardAmount,
		balance,
		invalidated > 0
	)
end

return HouseAttackCommitter
