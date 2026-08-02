local HouseAttackCommitter = require(script.Parent.HouseAttackCommitter)
local HouseTargetReservationService = require(script.Parent.HouseTargetReservationService)
local PlayerRuntimeHouseAttackAccess = require(script.Parent.PlayerRuntimeHouseAttackAccess)

local HouseAttackCommitService = {}

export type CommitOptions = {
	-- 允许怪兽与房屋水平包围盒之间存在的最大边缘距离。
	MaxGap: number,
	-- 本次命中对建筑造成的伤害。
	Damage: number,
	-- 本次成功摧毁房屋应增加的金钱；没有隐藏默认值。
	RewardAmount: number,
	-- 成功摧毁后获得奖励的进攻玩家。
	RewardPlayer: Player,
}

export type CommitResult = {
	-- 本次命中是否被服务器接受；非致命命中也为 true。
	Succeeded: boolean,
	-- 失败原因；成功时为 nil。
	Reason: string?,
	HouseId: string,
	Destroyed: boolean,
	-- HouseStateService 是否实际完成 Alive -> Destroyed。
	StateChanged: boolean,
	DamageApplied: number,
	PreviousHealth: number?,
	RemainingHealth: number?,
	MaxHealth: number?,
	HealthGeneration: number?,
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
--   options.Damage：本次命中的建筑伤害。
--   options.RewardAmount：成功摧毁后发放给 options.RewardPlayer 的奖励。
-- 输出：
--   返回命中血量、房屋状态变化、奖励、余额和预约释放结果。
-- 副作用：
--   重新校验后扣除会话血量；仅最后一击启动 Destroyed -> Rebuilding -> Alive，
--   并向最后一击玩家发放奖励；生命周期协调器负责全员表现广播。
--   本模块不选择下一栋房屋。
function HouseAttackCommitService.Commit(
	reservation: HouseTargetReservationService.Reservation,
	options: CommitOptions
): CommitResult
	return HouseAttackCommitter.Commit(reservation, PlayerRuntimeHouseAttackAccess, options)
end

return HouseAttackCommitService
