--[[
	职责：定义玩家持久化数据 Version 1，并把旧版本/合法原始表规范化。
	输入：DataStore 返回的 nil 或普通 Luau 表。
	输出：可序列化的 V1 数据；未来版本或损坏数据返回 nil 和原因。
	内部算法：nil 建默认档；V0 迁移到 V1；V1 逐字段白名单、数值约束和稳定键过滤。
	不负责：玩家、Instance、目录配置、DataStore、运行时状态或默认内容解锁。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local PlayerSaveSchema = {}

PlayerSaveSchema.CurrentVersion = 1
PlayerSaveSchema.ContentRevision = 6

local function nonNegative(value, fallback: number): number
	return if ValueValidation.IsFiniteNumber(value) and value >= 0
		then value
		else fallback
end

local function nonNegativeInteger(value, fallback: number): number
	return if ValueValidation.IsFiniteNumber(value)
		and value >= 0
		and value % 1 == 0
		then value
		else fallback
end

local function normalizeZones(values)
	local result = {}
	if type(values) ~= "table" then
		return result
	end
	for zoneId, value in values do
		if type(zoneId) == "string" and zoneId ~= "" and type(value) == "table" then
			result[zoneId] = {
				Unlocked = value.Unlocked == true,
				Level = nonNegativeInteger(value.Level, 0),
				IncomeMultiplier = nonNegative(value.IncomeMultiplier, 1),
				HealthMultiplier = nonNegative(value.HealthMultiplier, 1),
				BoostPurchased = value.BoostPurchased == true,
				AutoIncome = value.AutoIncome == true,
			}
		end
	end
	return result
end

local function normalizeHouses(values)
	local result = {}
	if type(values) ~= "table" then
		return result
	end
	for houseId, value in values do
		if type(houseId) == "string" and houseId ~= "" and type(value) == "table" then
			result[houseId] = {
				Built = value.Built == true,
				StoredMoney = nonNegative(value.StoredMoney, 0),
			}
		end
	end
	return result
end

local function normalizeSpawnPoints(values)
	local result = {}
	if type(values) ~= "table" then
		return result
	end
	for spawnPointId, value in values do
		if type(spawnPointId) == "string"
			and spawnPointId ~= ""
			and type(value) == "table" then
			local built = value.Built == true
			local level = nonNegativeInteger(value.Level, 0)
			local monsterKey = if type(value.MonsterKey) == "string" and value.MonsterKey ~= ""
				then value.MonsterKey
				else nil
			if built and (level < 1 or not monsterKey) then
				built = false
				level = 0
				monsterKey = nil
			end
			result[spawnPointId] = {
				Built = built,
				Level = level,
				MonsterKey = monsterKey,
			}
		end
	end
	return result
end

function PlayerSaveSchema.Default()
	return {
		Version = PlayerSaveSchema.CurrentVersion,
		ContentRevision = PlayerSaveSchema.ContentRevision,
		SavedAt = 0,
		Economy = { Money = 0 },
		Rebirth = {
			Count = 0,
			RunEarnings = 0,
		},
		Tutorial = { Version = 0 },
		Zones = {},
		Houses = {},
		Monsters = {
			Capacity = 1,
			SpawnPoints = {},
		},
	}
end

local function migrateV0(raw)
	return {
		Version = 1,
		ContentRevision = raw.ContentRevision,
		SavedAt = raw.SavedAt,
		Economy = raw.Economy or { Money = raw.Money },
		Rebirth = raw.Rebirth,
		Tutorial = raw.Tutorial,
		Zones = raw.Zones,
		Houses = raw.Houses,
		Monsters = raw.Monsters or {
			Capacity = raw.MonsterCapacity,
			SpawnPoints = raw.MonsterSpawnPoints,
		},
	}
end

function PlayerSaveSchema.Normalize(raw)
	if raw == nil then
		return PlayerSaveSchema.Default(), nil
	end
	if type(raw) ~= "table" then
		return nil, "CorruptSave"
	end

	local version = raw.Version
	if version == nil then
		version = 0
	end
	if type(version) ~= "number" or version % 1 ~= 0 or version < 0 then
		return nil, "InvalidSaveVersion"
	end
	if version > PlayerSaveSchema.CurrentVersion then
		return nil, "FutureSaveVersion"
	end
	if version == 0 then
		raw = migrateV0(raw)
		version = 1
	end
	if version ~= 1 then
		return nil, "UnsupportedSaveVersion"
	end

	local economy = if type(raw.Economy) == "table" then raw.Economy else {}
	local rebirth = if type(raw.Rebirth) == "table" then raw.Rebirth else {}
	local tutorial = if type(raw.Tutorial) == "table" then raw.Tutorial else {}
	local monsters = if type(raw.Monsters) == "table" then raw.Monsters else {}
	return {
		Version = 1,
		ContentRevision = nonNegativeInteger(raw.ContentRevision, 0),
		SavedAt = nonNegativeInteger(raw.SavedAt, 0),
		Economy = {
			Money = nonNegative(economy.Money, 0),
		},
		Rebirth = {
			Count = nonNegativeInteger(rebirth.Count, 0),
			RunEarnings = nonNegative(rebirth.RunEarnings, 0),
		},
		Tutorial = {
			Version = nonNegativeInteger(tutorial.Version, 0),
		},
		Zones = normalizeZones(raw.Zones),
		Houses = normalizeHouses(raw.Houses),
		Monsters = {
			Capacity = math.max(1, nonNegativeInteger(monsters.Capacity, 1)),
			SpawnPoints = normalizeSpawnPoints(monsters.SpawnPoints),
		},
	}, nil
end

return table.freeze(PlayerSaveSchema)
