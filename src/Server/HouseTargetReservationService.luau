local HouseTargetReservationService = {}

export type Reservation = {
	Id: number,
	Defender: Player,
	HouseId: string,
	Monster: Model,
	HealthGeneration: number,
}

local reservationsByDefender: {
	[Player]: { [string]: { [number]: Reservation } },
} = setmetatable(
	{},
	{ __mode = "k" }
)
local nextReservationId = 0

local function getDefenderReservations(defender: Player)
	local reservations = reservationsByDefender[defender]
	if not reservations then
		reservations = {}
		reservationsByDefender[defender] = reservations
	end

	return reservations
end

local function getHouseReservations(defender: Player, houseId: string)
	local reservations = getDefenderReservations(defender)
	local houseReservations = reservations[houseId]
	if not houseReservations then
		houseReservations = {}
		reservations[houseId] = houseReservations
	end
	return houseReservations
end

local function isMonsterInWorkspace(monster: Model): boolean
	return monster:IsDescendantOf(workspace)
end

local function clearStale(defender: Player, houseId: string)
	local reservations = reservationsByDefender[defender]
	local houseReservations = reservations and reservations[houseId]
	if not houseReservations then
		return
	end
	for id, reservation in houseReservations do
		if not isMonsterInWorkspace(reservation.Monster) then
			houseReservations[id] = nil
		end
	end
	if next(houseReservations) == nil then
		reservations[houseId] = nil
	end
end

-- 输入：
--   defender：被攻击房屋状态所属的玩家。
--   houseId：准备占用的稳定房屋 ID。
--   monster：准备攻击该房屋的 Workspace 怪兽模型。
--   healthGeneration：本次锁定的房屋血量代次。
-- 输出：
--   怪兽有效时返回不可变 Reservation；同一房屋允许多个怪兽同时持有凭证。
-- 副作用：成功时写入按 Player + HouseId + ReservationId 隔离的内存凭证。
function HouseTargetReservationService.TryAcquire(
	defender: Player,
	houseId: string,
	monster: Model,
	healthGeneration: number
): Reservation?
	assert(defender:IsA("Player"), "defender 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	assert(monster:IsA("Model"), "monster 必须是 Model")
	assert(
		type(healthGeneration) == "number"
			and healthGeneration >= 1
			and healthGeneration % 1 == 0,
		"healthGeneration 必须是正整数"
	)

	if not isMonsterInWorkspace(monster) then
		return nil
	end

	clearStale(defender, houseId)

	nextReservationId += 1
	local reservation = table.freeze({
		Id = nextReservationId,
		Defender = defender,
		HouseId = houseId,
		Monster = monster,
		HealthGeneration = healthGeneration,
	})
	getHouseReservations(defender, houseId)[reservation.Id] = reservation
	return reservation
end

-- 输入：
--   reservation：TryAcquire 返回的占用凭证。
-- 输出：
--   凭证仍登记在当前房屋且怪兽仍在 Workspace 时返回 true，否则返回 false。
-- 副作用：发现怪兽已离开 Workspace 时会清除对应的失效占用。
function HouseTargetReservationService.Validate(reservation: Reservation): boolean
	if type(reservation) ~= "table" then
		return false
	end

	local defender = reservation.Defender
	local houseId = reservation.HouseId
	local monster = reservation.Monster
	local healthGeneration = reservation.HealthGeneration
	if typeof(defender) ~= "Instance" or not defender:IsA("Player") then
		return false
	end
	if type(houseId) ~= "string" then
		return false
	end
	if typeof(monster) ~= "Instance" or not monster:IsA("Model") then
		return false
	end
	if type(healthGeneration) ~= "number" or healthGeneration < 1 or healthGeneration % 1 ~= 0 then
		return false
	end

	clearStale(defender, houseId)
	local reservations = reservationsByDefender[defender]
	local houseReservations = reservations and reservations[houseId]
	return houseReservations ~= nil and houseReservations[reservation.Id] == reservation
end

-- 输入：
--   reservation：准备释放的占用凭证。
-- 输出：
--   仅在凭证仍是当前占用且成功释放时返回 true。
-- 副作用：成功时删除对应的 Player + HouseId 内存占用状态。
function HouseTargetReservationService.Release(reservation: Reservation): boolean
	if not HouseTargetReservationService.Validate(reservation) then
		return false
	end

	local reservations = reservationsByDefender[reservation.Defender]
	local houseReservations = reservations and reservations[reservation.HouseId]
	if not houseReservations then
		return false
	end
	houseReservations[reservation.Id] = nil
	if next(houseReservations) == nil then
		reservations[reservation.HouseId] = nil
	end
	return true
end

-- 输入：防守玩家和房屋 ID。
-- 输出：被作废的当前战斗凭证数量。
-- 内部算法：整栋房屋摧毁时一次清空所有参与者凭证；其他房屋不受影响。
function HouseTargetReservationService.InvalidateHouse(defender: Player, houseId: string): number
	assert(defender:IsA("Player"), "defender 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	clearStale(defender, houseId)
	local reservations = reservationsByDefender[defender]
	local houseReservations = reservations and reservations[houseId]
	local count = 0
	if houseReservations then
		for _ in houseReservations do
			count += 1
		end
		reservations[houseId] = nil
	end
	return count
end

function HouseTargetReservationService.GetActiveCount(defender: Player, houseId: string): number
	assert(defender:IsA("Player"), "defender 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	clearStale(defender, houseId)
	local reservations = reservationsByDefender[defender]
	local houseReservations = reservations and reservations[houseId]
	local count = 0
	if houseReservations then
		for _ in houseReservations do
			count += 1
		end
	end
	return count
end

return HouseTargetReservationService
