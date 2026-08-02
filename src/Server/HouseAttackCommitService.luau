local CatalogHouseAttackAccess = require(script.Parent.CatalogHouseAttackAccess)
local HouseAttackCommitter = require(script.Parent.HouseAttackCommitter)
local HouseTargetReservationService = require(script.Parent.HouseTargetReservationService)

local HouseAttackCommitService = {}

export type CommitOptions = {
	-- 允许怪兽与房屋水平包围盒之间存在的最大边缘距离。
	MaxGap: number,
	-- 本次成功摧毁房屋应增加的金钱；没有隐藏默认值。
	RewardAmount: number,
	-- 成功摧毁后获得奖励的进攻玩家。
	RewardPlayer: Player,
}

export type CommitResult = {
	-- 本次提交是否成功摧毁房屋并发放奖励。
	Succeeded: boolean,
	-- 失败原因；成功时为 nil。
	Reason: string?,
	HouseId: string,
	-- HouseStateService 是否实际完成 Alive -> Destroyed。
	StateChanged: boolean,
	-- 本次实际发放的奖励；失败时为 0。
	RewardGranted: number,
	-- 发放奖励后的余额；没有发放时为 nil。
	Balance: number?,
	-- 本次提交是否成功释放了预约。
	ReservationReleased: boolean,
}

-- 输入：
--   reservation：HouseTargetReservationService.TryAcquire 返回的当前占用凭证。
--   options.MaxGap：提交时允许的最大水平边缘间距。
--   options.RewardAmount：成功摧毁后发放给 options.RewardPlayer 的奖励。
-- 输出：
--   返回房屋状态变化、奖励、余额和预约释放结果；所有业务失败都通过 Reason 明示。
-- 副作用：
--   重新校验后可能把房屋切换为 Destroyed、增加玩家金钱，并消费预约。
--   不播放动画、不选择下一栋房屋、不发送 RemoteEvent。
function HouseAttackCommitService.Commit(
	reservation: HouseTargetReservationService.Reservation,
	options: CommitOptions
): CommitResult
	return HouseAttackCommitter.Commit(reservation, CatalogHouseAttackAccess, options)
end

return HouseAttackCommitService
