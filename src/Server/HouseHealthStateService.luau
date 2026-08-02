--[[
	职责：保存每名在线玩家每栋房屋的服务器会话血量和战斗代次。
	输入：Player、HouseId；初始化/迁移额外接收等级和最大生命，伤害额外接收预期代次。
	输出：当前快照、伤害结果、迁移或回滚是否成功。
	内部算法：首次访问满血；等级变化按比例迁移并递增代次；重建满血并递增代次；
		伤害只接受当前代次，确保旧战斗凭证无法命中新一轮建筑。
	不负责：解析配置、读取模型、生命周期、奖励、表现或持久化。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StructureHealthRules = require(
	ReplicatedStorage.Shared.Building.StructureHealthRules
)

local HouseHealthStateService = {}

export type Snapshot = {
	HouseId: string,
	Level: number,
	CurrentHealth: number,
	MaxHealth: number,
	Generation: number,
}

export type DamageResult = {
	Accepted: boolean,
	Reason: string?,
	HouseId: string,
	Level: number?,
	Generation: number?,
	PreviousHealth: number?,
	CurrentHealth: number?,
	MaxHealth: number?,
	DamageApplied: number,
	Depleted: boolean,
}

type Record = Snapshot

local recordsByPlayer: { [Player]: { [string]: Record } } = setmetatable({}, { __mode = "k" })

local function assertIdentity(player: Player, houseId: string)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
end

local function assertDefinition(level: number, maxHealth: number)
	assert(type(level) == "number" and level >= 1 and level % 1 == 0, "level 必须是正整数")
	assert(
		type(maxHealth) == "number"
			and maxHealth == maxHealth
			and maxHealth < math.huge
			and maxHealth > 0,
		"maxHealth 必须是有限正数"
	)
end

local function snapshot(record: Record): Snapshot
	return {
		HouseId = record.HouseId,
		Level = record.Level,
		CurrentHealth = record.CurrentHealth,
		MaxHealth = record.MaxHealth,
		Generation = record.Generation,
	}
end

local function getPlayerRecords(player: Player): { [string]: Record }
	local records = recordsByPlayer[player]
	if not records then
		records = {}
		recordsByPlayer[player] = records
	end
	return records
end

function HouseHealthStateService.Get(player: Player, houseId: string): Snapshot?
	assertIdentity(player, houseId)
	local records = recordsByPlayer[player]
	local record = records and records[houseId]
	return if record then snapshot(record) else nil
end

function HouseHealthStateService.Ensure(
	player: Player,
	houseId: string,
	level: number,
	maxHealth: number
): Snapshot
	assertIdentity(player, houseId)
	assertDefinition(level, maxHealth)
	local records = getPlayerRecords(player)
	local record = records[houseId]
	if not record then
		record = {
			HouseId = houseId,
			Level = level,
			CurrentHealth = maxHealth,
			MaxHealth = maxHealth,
			Generation = 1,
		}
		records[houseId] = record
	elseif record.Level ~= level or record.MaxHealth ~= maxHealth then
		local migrated = assert(StructureHealthRules.MigrateByRatio(
			record.CurrentHealth,
			record.MaxHealth,
			maxHealth
		))
		record.Level = level
		record.CurrentHealth = migrated
		record.MaxHealth = maxHealth
		record.Generation += 1
	end
	return snapshot(record)
end

function HouseHealthStateService.ResetFull(
	player: Player,
	houseId: string,
	level: number,
	maxHealth: number
): Snapshot
	assertIdentity(player, houseId)
	assertDefinition(level, maxHealth)
	local records = getPlayerRecords(player)
	local previous = records[houseId]
	local record = {
		HouseId = houseId,
		Level = level,
		CurrentHealth = maxHealth,
		MaxHealth = maxHealth,
		Generation = if previous then previous.Generation + 1 else 1,
	}
	records[houseId] = record
	return snapshot(record)
end

function HouseHealthStateService.ApplyDamage(
	player: Player,
	houseId: string,
	expectedGeneration: number,
	damage: number
): DamageResult
	assertIdentity(player, houseId)
	local records = recordsByPlayer[player]
	local record = records and records[houseId]
	if not record then
		return {
			Accepted = false,
			Reason = "HealthStateUnavailable",
			HouseId = houseId,
			Level = nil,
			Generation = nil,
			PreviousHealth = nil,
			CurrentHealth = nil,
			MaxHealth = nil,
			DamageApplied = 0,
			Depleted = false,
		}
	end
	if expectedGeneration ~= record.Generation then
		return {
			Accepted = false,
			Reason = "StaleHealthGeneration",
			HouseId = houseId,
			Level = record.Level,
			Generation = record.Generation,
			PreviousHealth = record.CurrentHealth,
			CurrentHealth = record.CurrentHealth,
			MaxHealth = record.MaxHealth,
			DamageApplied = 0,
			Depleted = record.CurrentHealth == 0,
		}
	end

	local applied = StructureHealthRules.ApplyDamage(
		record.CurrentHealth,
		record.MaxHealth,
		damage
	)
	if applied.Accepted then
		record.CurrentHealth = applied.RemainingHealth
	end
	return {
		Accepted = applied.Accepted,
		Reason = applied.Reason,
		HouseId = houseId,
		Level = record.Level,
		Generation = record.Generation,
		PreviousHealth = applied.PreviousHealth,
		CurrentHealth = applied.RemainingHealth,
		MaxHealth = record.MaxHealth,
		DamageApplied = applied.DamageApplied,
		Depleted = applied.Depleted,
	}
end

function HouseHealthStateService.RollbackDamage(
	player: Player,
	houseId: string,
	expectedGeneration: number,
	previousHealth: number
): boolean
	assertIdentity(player, houseId)
	local records = recordsByPlayer[player]
	local record = records and records[houseId]
	if not record
		or record.Generation ~= expectedGeneration
		or record.CurrentHealth ~= 0
		or type(previousHealth) ~= "number"
		or previousHealth <= 0
		or previousHealth > record.MaxHealth then
		return false
	end
	record.CurrentHealth = previousHealth
	return true
end

function HouseHealthStateService.Clear(player: Player): number
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local records = recordsByPlayer[player]
	local count = 0
	if records then
		for _ in records do
			count += 1
		end
	end
	recordsByPlayer[player] = nil
	return count
end

return HouseHealthStateService
