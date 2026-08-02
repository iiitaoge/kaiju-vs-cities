local HouseAttackGeometry = require(script.Parent.HouseAttackGeometry)
local HouseAttackTargetAccess = require(script.Parent.HouseAttackTargetAccess)
local HouseTargetReservationService = require(script.Parent.HouseTargetReservationService)
local MoneyService = require(script.Parent.MoneyService)

local HouseAttackCommitter = {}

export type CommitOptions = {
	-- 允许怪兽与房屋水平包围盒之间存在的最大边缘距离。
	MaxGap: number,
	-- 本次成功摧毁房屋应增加的金钱；没有隐藏默认值。
	RewardAmount: number,
}

export type CommitResult = {
	Succeeded: boolean,
	Reason: string?,
	HouseId: string,
	StateChanged: boolean,
	RewardGranted: number,
	Balance: number?,
	ReservationReleased: boolean,
}

local function makeResult(
	houseId: string,
	succeeded: boolean,
	reason: string?,
	stateChanged: boolean,
	rewardGranted: number,
	balance: number?,
	reservationReleased: boolean
): CommitResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		HouseId = houseId,
		StateChanged = stateChanged,
		RewardGranted = rewardGranted,
		Balance = balance,
		ReservationReleased = reservationReleased,
	}
end

-- 输入：
--   reservation：当前怪兽对房屋的有效预约。
--   access：显式房屋数据源，负责最新范围、摧毁前准备和状态切换。
--   options.MaxGap：提交时允许的最大水平边缘间距。
--   options.RewardAmount：成功摧毁后发放给 reservation.Player 的奖励。
-- 输出：
--   返回房屋状态变化、奖励、余额和预约释放结果；业务失败通过 Reason 明示。
-- 副作用：
--   可能通过 access 切换房屋状态、增加玩家金钱，并消费预约。
--   不播放动画、不选择下一栋房屋、不发送 RemoteEvent。
function HouseAttackCommitter.Commit(
	reservation: HouseTargetReservationService.Reservation,
	access: HouseAttackTargetAccess.Access,
	options: CommitOptions
): CommitResult
	assert(type(access) == "table", "access 必须是 HouseAttackTargetAccess.Access")
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.MaxGap) == "number" and options.MaxGap >= 0, "MaxGap 必须大于等于 0")
	assert(
		type(options.RewardAmount) == "number" and options.RewardAmount >= 0,
		"RewardAmount 必须大于等于 0"
	)

	local houseId = if type(reservation) == "table" and type(reservation.HouseId) == "string"
		then reservation.HouseId
		else ""
	if not HouseTargetReservationService.Validate(reservation) then
		return makeResult(houseId, false, "InvalidReservation", false, 0, nil, false)
	end

	local function fail(reason: string): CommitResult
		local released = HouseTargetReservationService.Release(reservation)
		return makeResult(houseId, false, reason, false, 0, nil, released)
	end

	local target, resolveReason = access.ResolveAliveTarget(reservation.Player, houseId)
	if not target then
		return fail(resolveReason or "HouseUnavailable")
	end

	local gap = HouseAttackGeometry.GetGap(reservation.Monster, target)
	if gap > options.MaxGap then
		return fail("OutOfRange")
	end

	local prepared, prepareReason = access.PrepareDestroy(reservation.Player, houseId)
	if not prepared then
		return fail(prepareReason or "PrepareDestroyFailed")
	end

	if not access.Destroy(reservation.Player, houseId) then
		return fail("DestroyRejected")
	end

	local balance = MoneyService.Add(reservation.Player, options.RewardAmount)
	local released = HouseTargetReservationService.Release(reservation)
	return makeResult(
		houseId,
		true,
		nil,
		true,
		options.RewardAmount,
		balance,
		released
	)
end

return HouseAttackCommitter
