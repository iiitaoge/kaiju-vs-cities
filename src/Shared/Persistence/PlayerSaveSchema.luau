--[[
	职责：定义玩家持久化数据 Version 1，并把旧版本/合法原始表规范化。
	输入：DataStore 返回的 nil 或普通 Luau 表。
	输出：可序列化的 V1 数据；未来版本或损坏数据返回 nil 和原因。
	内部算法：nil 建默认档；V0 迁移到 V1；V1 逐字段白名单、数值约束和稳定键过滤。
	不负责：玩家、Instance、目录配置、DataStore、运行时状态或默认内容解锁。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)
local VehicleProgressionConfigs = require(
	script.Parent.Parent.Vehicle.VehicleProgressionConfigs
)

local PlayerSaveSchema = {}

PlayerSaveSchema.CurrentVersion = 1
PlayerSaveSchema.ContentRevision = 9

local DAILY_REWARD_COMPLETED_DAY = 8

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

local function normalizeDailyReward(values)
	local source = if type(values) == "table" then values else {}
	local day = math.clamp(
		nonNegativeInteger(source.Day, 1),
		1,
		DAILY_REWARD_COMPLETED_DAY
	)
	return {
		Day = day,
		NextClaimAt = if day == DAILY_REWARD_COMPLETED_DAY
			then 0
			else nonNegativeInteger(source.NextClaimAt, 0),
	}
end

local function isValidGroupRewardId(value): boolean
	return type(value) == "string"
		and value ~= ""
		and string.match(value, "^[A-Za-z0-9_.%-]+$") ~= nil
end

local function normalizeGroupRewardClaims(values)
	local result = {}
	if type(values) ~= "table" then
		return result
	end
	for rewardId, claimed in values do
		if isValidGroupRewardId(rewardId) and claimed == true then
			result[rewardId] = true
		end
	end
	return result
end

local function normalizeTasks(values)
	local result = {}
	if type(values) ~= "table" then
		return result
	end
	for taskId, value in values do
		if isValidGroupRewardId(taskId) and type(value) == "table" then
			local progress = {}
			if type(value.Progress) == "table" then
				for requirementId, requirementProgress in value.Progress do
					if isValidGroupRewardId(requirementId) and type(requirementProgress) == "table" then
						local progressKind = if type(requirementProgress.Kind) == "string"
							and requirementProgress.Kind ~= ""
						then requirementProgress.Kind
						else "Unknown"
						progress[requirementId] = {
							Kind = progressKind,
							Current = nonNegative(requirementProgress.Current, 0),
							Completed = requirementProgress.Completed == true,
						}
					end
				end
			end
			result[taskId] = {
				Completed = value.Completed == true,
				Progress = progress,
			}
		end
	end
	return result
end

local function normalizeVehicles(values)
	local result = {}
	if type(values) ~= "table" then
		return result
	end
	for instanceId, value in values do
		if type(instanceId) == "string"
			and instanceId ~= ""
			and string.match(instanceId, "^[A-Za-z0-9_.%-]+$") ~= nil
			and type(value) == "table"
		then
			local vehicleId = value.VehicleId
			local level = value.Level
			if type(vehicleId) == "string"
				and vehicleId ~= ""
				and string.match(vehicleId, "^[A-Za-z0-9_.%-]+$") ~= nil
				and type(level) == "number"
				and level == level
				and level < math.huge
				and level >= 1
				and level % 1 == 0
			then
				result[instanceId] = {
					VehicleId = vehicleId,
					Level = math.clamp(level, 1, VehicleProgressionConfigs.MaxLevel),
				}
			end
		end
	end
	return result
end

local function isValidPurchaseId(value): boolean
	return type(value) == "string"
		and value ~= ""
		and #value <= 128
		and string.match(value, "^[A-Za-z0-9_.%-]+$") ~= nil
end

local function normalizePurchases(values)
	local result = {
		ProcessedPurchaseIds = {},
		PendingMonsterUpgrade = nil,
	}
	if type(values) ~= "table" then
		return result
	end

	if type(values.ProcessedPurchaseIds) == "table" then
		for purchaseId, processed in values.ProcessedPurchaseIds do
			if processed == true and isValidPurchaseId(purchaseId) then
				result.ProcessedPurchaseIds[purchaseId] = true
			end
		end
	end

	local pending = values.PendingMonsterUpgrade
	if type(pending) == "table"
		and type(pending.ProductId) == "number"
		and pending.ProductId > 0
		and pending.ProductId < math.huge
		and pending.ProductId % 1 == 0
		and type(pending.SpawnPointId) == "string"
		and pending.SpawnPointId ~= ""
		and #pending.SpawnPointId <= 64
		and string.match(pending.SpawnPointId, "^[A-Za-z0-9_.%-]+$") ~= nil
	then
		result.PendingMonsterUpgrade = {
			ProductId = pending.ProductId,
			SpawnPointId = pending.SpawnPointId,
		}
	end
	return result
end

function PlayerSaveSchema.Default()
	return {
		Version = PlayerSaveSchema.CurrentVersion,
		ContentRevision = PlayerSaveSchema.ContentRevision,
		SavedAt = 0,
		Economy = { Money = 0, Diamond = 0 },
		DailyReward = {
			Day = 1,
			NextClaimAt = 0,
		},
		GroupRewardClaims = {},
		Tasks = {},
		Vehicles = {},
		Purchases = {
			ProcessedPurchaseIds = {},
			PendingMonsterUpgrade = nil,
		},
		Rebirth = {
			Count = 0,
			RunEarnings = 0,
		},
		Tutorial = {
			Version = 0,
			AttackCompleted = false,
		},
		Zones = {},
		Houses = {},
		Monsters = {
			Capacity = 1,
			SpawnPoints = {},
		},
		DefenseMonsters = {
			SpawnPoints = {},
		},
	}
end

local function migrateV0(raw)
	return {
		Version = 1,
		ContentRevision = raw.ContentRevision,
		SavedAt = raw.SavedAt,
		Economy = raw.Economy or { Money = raw.Money, Diamond = raw.Diamond },
		DailyReward = raw.DailyReward,
		GroupRewardClaims = raw.GroupRewardClaims,
		Tasks = raw.Tasks,
		Vehicles = raw.Vehicles,
		Purchases = raw.Purchases,
		Rebirth = raw.Rebirth,
		Tutorial = raw.Tutorial,
		Zones = raw.Zones,
		Houses = raw.Houses,
		Monsters = raw.Monsters or {
			Capacity = raw.MonsterCapacity,
			SpawnPoints = raw.MonsterSpawnPoints,
		},
		DefenseMonsters = raw.DefenseMonsters,
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
	local dailyReward = if type(raw.DailyReward) == "table" then raw.DailyReward else {}
	local groupRewardClaims = normalizeGroupRewardClaims(raw.GroupRewardClaims)
	local tasks = normalizeTasks(raw.Tasks)
	local rebirth = if type(raw.Rebirth) == "table" then raw.Rebirth else {}
	local tutorial = if type(raw.Tutorial) == "table" then raw.Tutorial else {}
	local monsters = if type(raw.Monsters) == "table" then raw.Monsters else {}
	local defenseMonsters = if type(raw.DefenseMonsters) == "table" then raw.DefenseMonsters else {}
	local purchases = normalizePurchases(raw.Purchases)
	return {
		Version = 1,
		ContentRevision = nonNegativeInteger(raw.ContentRevision, 0),
		SavedAt = nonNegativeInteger(raw.SavedAt, 0),
		Economy = {
			Money = nonNegative(economy.Money, 0),
			Diamond = nonNegative(economy.Diamond, 0),
		},
		DailyReward = normalizeDailyReward(dailyReward),
		GroupRewardClaims = groupRewardClaims,
		Tasks = tasks,
		Vehicles = normalizeVehicles(raw.Vehicles),
		Purchases = purchases,
		Rebirth = {
			Count = nonNegativeInteger(rebirth.Count, 0),
			RunEarnings = nonNegative(rebirth.RunEarnings, 0),
		},
		Tutorial = {
			Version = nonNegativeInteger(tutorial.Version, 0),
			AttackCompleted = tutorial.AttackCompleted == true,
		},
		Zones = normalizeZones(raw.Zones),
		Houses = normalizeHouses(raw.Houses),
		Monsters = {
			Capacity = math.max(1, nonNegativeInteger(monsters.Capacity, 1)),
			SpawnPoints = normalizeSpawnPoints(monsters.SpawnPoints),
		},
		DefenseMonsters = {
			SpawnPoints = normalizeSpawnPoints(defenseMonsters.SpawnPoints),
		},
	}, nil
end

return table.freeze(PlayerSaveSchema)
