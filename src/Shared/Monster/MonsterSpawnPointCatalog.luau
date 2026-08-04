--[[
	职责：定义出生点稳定身份，以及出生点等级对应的 MonsterKey。
	不负责：玩家是否已建造、Zone 是否解锁、容量或模型生成。
]]

local MonsterCatalog = require(script.Parent.MonsterCatalog)

local MonsterSpawnPointCatalog = {}

export type Definition = {
	SpawnPointId: string,
	ZoneId: string,
	SlotId: string,
	ProgressionId: string,
	RequiredBuiltSpawnPointId: string?,
}

local definitions: { [string]: Definition } = {
	["M1-S1"] = {
		SpawnPointId = "M1-S1",
		ZoneId = "M1",
		SlotId = "M1-S1",
		ProgressionId = "Godzilla",
	},
	["M1-S2"] = {
		SpawnPointId = "M1-S2",
		ZoneId = "M1",
		SlotId = "M1-S2",
		ProgressionId = "Godzilla",
		RequiredBuiltSpawnPointId = "M1-S1",
	},
	["M1-S3"] = {
		SpawnPointId = "M1-S3",
		ZoneId = "M1",
		SlotId = "M1-S3",
		ProgressionId = "Godzilla",
		RequiredBuiltSpawnPointId = "M1-S2",
	},
	["M1-S4"] = {
		SpawnPointId = "M1-S4",
		ZoneId = "M1",
		SlotId = "M1-S4",
		ProgressionId = "Godzilla",
		RequiredBuiltSpawnPointId = "M1-S3",
	},
}

local sortedDefinitions = {}
for spawnPointId, definition in pairs(definitions) do
	assert(
		definition.SpawnPointId == spawnPointId,
		"SpawnPointId 与配置键不一致：" .. spawnPointId
	)
	assert(type(definition.ZoneId) == "string" and definition.ZoneId ~= "", "ZoneId 无效")
	assert(type(definition.SlotId) == "string" and definition.SlotId ~= "", "SlotId 无效")
	assert(MonsterCatalog.GetMonsterKey(definition.ProgressionId, 1) ~= nil, "出生点必须配置有效成长线")
	if definition.RequiredBuiltSpawnPointId then
		assert(
			definitions[definition.RequiredBuiltSpawnPointId] ~= nil,
			spawnPointId .. " 前置出生点无效"
		)
	end
	table.freeze(definition)
	table.insert(sortedDefinitions, definition)
end

table.sort(sortedDefinitions, function(a, b)
	return a.SpawnPointId < b.SpawnPointId
end)
table.freeze(sortedDefinitions)
table.freeze(definitions)

function MonsterSpawnPointCatalog.Get(spawnPointId: string): Definition?
	return definitions[spawnPointId]
end

function MonsterSpawnPointCatalog.GetMonsterKey(spawnPointId: string, level: number): string?
	local definition = definitions[spawnPointId]
	return if definition then MonsterCatalog.GetMonsterKey(definition.ProgressionId, level) else nil
end

function MonsterSpawnPointCatalog.GetMaxLevel(spawnPointId: string): number?
	local definition = definitions[spawnPointId]
	return if definition then MonsterCatalog.GetMaxLevel(definition.ProgressionId) else nil
end

function MonsterSpawnPointCatalog.GetAll(): { Definition }
	return table.clone(sortedDefinitions)
end

return MonsterSpawnPointCatalog
