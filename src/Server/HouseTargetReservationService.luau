local HouseTargetReservationService = {}

export type Reservation = {
	Id: number,
	Player: Player,
	HouseId: string,
	Monster: Model,
}

local reservationsByPlayer: { [Player]: { [string]: Reservation } } = setmetatable(
	{},
	{ __mode = "k" }
)
local nextReservationId = 0

local function getPlayerReservations(player: Player)
	local reservations = reservationsByPlayer[player]
	if not reservations then
		reservations = {}
		reservationsByPlayer[player] = reservations
	end

	return reservations
end

local function isMonsterInWorkspace(monster: Model): boolean
	return monster:IsDescendantOf(workspace)
end

local function clearIfStale(player: Player, houseId: string): Reservation?
	local reservations = reservationsByPlayer[player]
	local reservation = reservations and reservations[houseId]
	if reservation and not isMonsterInWorkspace(reservation.Monster) then
		reservations[houseId] = nil
		return nil
	end

	return reservation
end

-- 输入：
--   player：被攻击房屋状态所属的玩家。
--   houseId：准备占用的稳定房屋 ID。
--   monster：准备攻击该房屋的 Workspace 怪兽模型。
-- 输出：
--   占用成功时返回不可变 Reservation；已被占用或怪兽不在 Workspace 时返回 nil。
-- 副作用：成功时写入按 Player + HouseId 隔离的内存占用状态。
function HouseTargetReservationService.TryAcquire(
	player: Player,
	houseId: string,
	monster: Model
): Reservation?
	assert(player:IsA("Player"), "player 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	assert(monster:IsA("Model"), "monster 必须是 Model")

	if not isMonsterInWorkspace(monster) then
		return nil
	end

	if clearIfStale(player, houseId) then
		return nil
	end

	nextReservationId += 1
	local reservation = table.freeze({
		Id = nextReservationId,
		Player = player,
		HouseId = houseId,
		Monster = monster,
	})
	getPlayerReservations(player)[houseId] = reservation
	return reservation
end

-- 输入：
--   reservation：TryAcquire 返回的占用凭证。
-- 输出：
--   凭证仍是当前占用且怪兽仍在 Workspace 时返回 true，否则返回 false。
-- 副作用：发现怪兽已离开 Workspace 时会清除对应的失效占用。
function HouseTargetReservationService.Validate(reservation: Reservation): boolean
	if type(reservation) ~= "table" then
		return false
	end

	local player = reservation.Player
	local houseId = reservation.HouseId
	local monster = reservation.Monster
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if type(houseId) ~= "string" then
		return false
	end
	if typeof(monster) ~= "Instance" or not monster:IsA("Model") then
		return false
	end

	local current = clearIfStale(player, houseId)
	return current == reservation
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

	local reservations = reservationsByPlayer[reservation.Player]
	reservations[reservation.HouseId] = nil
	return true
end

return HouseTargetReservationService
