--[[
	职责：串行化同一玩家同一产钱区域的服务器事务。
	输入：Player、RegionId。
	输出：成功时返回一次性 Release；忙碌时返回 nil。
	内部算法：弱键索引 Player，再按 RegionId 标记；不依赖任何业务模块。
]]

local PlayerRegionTransactionLock = {}

local locks: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" })
local exclusiveLocks: { [Player]: boolean } = setmetatable({}, { __mode = "k" })

function PlayerRegionTransactionLock.TryAcquire(
	player: Player,
	regionId: string
): (() -> ())?
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(regionId) == "string" and regionId ~= "", "regionId 必须是非空字符串")
	if exclusiveLocks[player] then
		return nil
	end
	local playerLocks = locks[player]
	if not playerLocks then
		playerLocks = {}
		locks[player] = playerLocks
	end
	if playerLocks[regionId] then
		return nil
	end

	playerLocks[regionId] = true
	local released = false
	return function()
		if released then
			return
		end
		released = true
		playerLocks[regionId] = nil
		if next(playerLocks) == nil then
			locks[player] = nil
		end
	end
end

function PlayerRegionTransactionLock.IsAnyLocked(player: Player): boolean
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local playerLocks = locks[player]
	return exclusiveLocks[player] == true
		or (playerLocks ~= nil and next(playerLocks) ~= nil)
end

function PlayerRegionTransactionLock.TryAcquireExclusive(player: Player): (() -> ())?
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	if PlayerRegionTransactionLock.IsAnyLocked(player) then
		return nil
	end
	exclusiveLocks[player] = true
	local released = false
	return function()
		if released then
			return
		end
		released = true
		exclusiveLocks[player] = nil
	end
end

return table.freeze(PlayerRegionTransactionLock)
