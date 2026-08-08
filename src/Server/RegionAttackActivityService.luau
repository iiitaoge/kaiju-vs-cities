--[[
	职责：维护防守玩家各区域当前的进攻占用。
	输入：防守玩家和 RegionId；攻击命令开始时尝试占用，结束时释放。
	输出：区域是否正在被攻击，以及一次性释放函数。
	内部算法：弱键索引 Player，再按 RegionId 做不可并发占用；TryAcquire 不产生等待，保证同一服务器线程内原子竞争。
	不负责：怪兽状态、区域几何校验、攻击执行或客户端提示。
]]

local RegionAttackActivityService = {}

local locks: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" })

function RegionAttackActivityService.TryAcquire(
	defender: Player,
	regionId: string
): (() -> ())?
	assert(typeof(defender) == "Instance" and defender:IsA("Player"), "defender 必须是 Player")
	assert(type(regionId) == "string" and regionId ~= "", "regionId 必须是非空字符串")

	local defenderLocks = locks[defender]
	if defenderLocks and defenderLocks[regionId] then
		return nil
	end
	if not defenderLocks then
		defenderLocks = {}
		locks[defender] = defenderLocks
	end

	defenderLocks[regionId] = true
	local released = false
	return function()
		if released then
			return
		end
		released = true
		defenderLocks[regionId] = nil
		if next(defenderLocks) == nil then
			locks[defender] = nil
		end
	end
end

function RegionAttackActivityService.IsActive(defender: Player, regionId: string): boolean
	assert(typeof(defender) == "Instance" and defender:IsA("Player"), "defender 必须是 Player")
	assert(type(regionId) == "string" and regionId ~= "", "regionId 必须是非空字符串")
	local defenderLocks = locks[defender]
	return defenderLocks ~= nil and defenderLocks[regionId] == true
end

return table.freeze(RegionAttackActivityService)
