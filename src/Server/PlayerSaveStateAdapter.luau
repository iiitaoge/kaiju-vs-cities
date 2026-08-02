--[[
	职责：在版本化存档表与服务器运行时状态服务之间做白名单转换。
	输入：Capture 接收 player；Apply 接收 player、已由 PlayerSaveSchema 规范化的数据和时间。
	输出：Capture 返回 V1 可序列化表；Apply 返回实际恢复的内容计数。
	内部算法：只遍历当前 Catalog；新内容取配置默认值，旧存档中的未知内容被忽略。
	不负责：DataStore、Plot/模型生成、攻击状态、临时生命值、奖励或表现。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseStateService = require(script.Parent.HouseStateService)
local MoneyService = require(script.Parent.MoneyService)
local MonsterSpawnPointStateService = require(script.Parent.MonsterSpawnPointStateService)
local MonsterStateService = require(script.Parent.MonsterStateService)
local RegionStateService = require(script.Parent.RegionStateService)
local RegionUpgradeConfigs = require(script.Parent.RegionUpgradeConfigs)
local ZoneStateService = require(script.Parent.ZoneStateService)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local MonsterCapacityConfig = require(ReplicatedStorage.Shared.Monster.MonsterCapacityConfig)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)
local PlayerSaveSchema = require(ReplicatedStorage.Shared.Persistence.PlayerSaveSchema)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local PlayerSaveStateAdapter = {}

local function getMaxConfiguredLevel(zoneId: string): number?
	local config = RegionUpgradeConfigs[zoneId]
	if not config then
		return nil
	end
	local maxLevel = 0
	for level in config.Levels do
		if type(level) == "number" and level % 1 == 0 and level > maxLevel then
			maxLevel = level
		end
	end
	return maxLevel
end

local function restoreZone(player: Player, definition, savedZone)
	local unlocked = definition.InitialUnlocked or (savedZone and savedZone.Unlocked == true) or false
	local level = if savedZone then savedZone.Level else 0
	if not unlocked then
		level = 0
	end
	local maxLevel = getMaxConfiguredLevel(definition.ZoneId)
	if maxLevel then
		level = math.clamp(level, 0, maxLevel)
	end

	ZoneStateService.SetUnlocked(player, definition.ZoneId, unlocked)
	ZoneStateService.SetLevel(player, definition.ZoneId, level)
	if definition.Kind == "Income" then
		RegionStateService.SetIncomeMultiplier(
			player,
			definition.ZoneId,
			if savedZone then savedZone.IncomeMultiplier else 1
		)
		RegionStateService.SetAutoIncome(
			player,
			definition.ZoneId,
			if savedZone then savedZone.AutoIncome else false
		)
	end
end

function PlayerSaveStateAdapter.Apply(player: Player, data, now: number?)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(data) == "table" and data.Version == PlayerSaveSchema.CurrentVersion, "data 必须是当前版本存档")
	local restoredAt = now or os.time()

	MoneyService.Set(player, data.Economy.Money)
	for _, definition in ZoneCatalog.GetAll() do
		restoreZone(player, definition, data.Zones[definition.ZoneId])
	end

	local houseCount = 0
	for _, definition in HouseCatalog.GetAll() do
		local saved = data.Houses[definition.HouseId]
		local built = saved ~= nil
			and saved.Built == true
			and ZoneStateService.GetUnlocked(player, definition.RegionId)
			and ZoneStateService.GetLevel(player, definition.RegionId) > 0
		local storedMoney = if built then saved.StoredMoney else 0
		HouseStateService.RestoreDurable(
			player,
			definition.HouseId,
			built,
			storedMoney,
			restoredAt
		)
		if built then
			houseCount += 1
		end
	end

	-- Monsters 分区只保存容量；所有实体状态由 durable 出生点重新创建。
	MonsterStateService.ClearSession(player)
	MonsterStateService.SetCapacity(
		player,
		math.max(MonsterCapacityConfig.InitialCapacity, data.Monsters.Capacity)
	)
	local spawnPointCount = 0
	for _, definition in MonsterSpawnPointCatalog.GetAll() do
		local saved = data.Monsters.SpawnPoints[definition.SpawnPointId]
		local built = saved ~= nil
			and saved.Built == true
			and ZoneStateService.GetUnlocked(player, definition.ZoneId)
			and definition.MonsterKeyByLevel[saved.Level] == saved.MonsterKey
		MonsterSpawnPointStateService.Restore(
			player,
			definition.SpawnPointId,
			built,
			if built then saved.Level else 0,
			if built then saved.MonsterKey else nil
		)
		if built then
			spawnPointCount += 1
		end
	end

	return {
		HouseCount = houseCount,
		SpawnPointCount = spawnPointCount,
	}
end

function PlayerSaveStateAdapter.Capture(player: Player, now: number?)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local zones = {}
	for _, definition in ZoneCatalog.GetAll() do
		local zone = ZoneStateService.Get(player, definition.ZoneId)
		zones[definition.ZoneId] = {
			Unlocked = zone.Unlocked,
			Level = zone.Level,
			IncomeMultiplier = if definition.Kind == "Income"
				then RegionStateService.GetIncomeMultiplier(player, definition.ZoneId)
				else 1,
			AutoIncome = if definition.Kind == "Income"
				then RegionStateService.GetAutoIncome(player, definition.ZoneId)
				else false,
		}
	end

	local houses = {}
	for _, definition in HouseCatalog.GetAll() do
		local state = HouseStateService.Get(player, definition.HouseId)
		houses[definition.HouseId] = {
			Built = state.LifeState ~= "Unbuilt",
			StoredMoney = state.StoredMoney or 0,
		}
	end

	local spawnPoints = {}
	for _, definition in MonsterSpawnPointCatalog.GetAll() do
		local state = MonsterSpawnPointStateService.Get(player, definition.SpawnPointId)
		spawnPoints[definition.SpawnPointId] = {
			Built = state.Built,
			Level = state.Level,
			MonsterKey = state.MonsterKey,
		}
	end

	return {
		Version = PlayerSaveSchema.CurrentVersion,
		ContentRevision = PlayerSaveSchema.ContentRevision,
		SavedAt = now or os.time(),
		Economy = { Money = MoneyService.Get(player) },
		Zones = zones,
		Houses = houses,
		Monsters = {
			Capacity = MonsterStateService.GetCapacity(player),
			SpawnPoints = spawnPoints,
		},
	}
end

return PlayerSaveStateAdapter
