--[[
	职责：定义出生点稳定身份，以及出生点等级对应的 MonsterKey。
	不负责：玩家是否已建造、Zone 是否解锁、容量或模型生成。
]]

local MonsterSpawnPointCatalog = {}

export type Definition = {
	SpawnPointId: string,
	ZoneId: string,
	SlotId: string,
	MonsterKeyByLevel: { [number]: string },
}

local definitions: { [string]: Definition } = {
	["M1-S1"] = {
		SpawnPointId = "M1-S1",
		ZoneId = "M1",
		SlotId = "M1-S1",
		MonsterKeyByLevel = {
			[1] = "P1",
			[2] = "P4",
		},
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
	assert(definition.MonsterKeyByLevel[1] ~= nil, "出生点必须配置等级 1 怪兽")

	for level, monsterKey in pairs(definition.MonsterKeyByLevel) do
		assert(type(level) == "number" and level >= 1 and level % 1 == 0, "出生点等级无效")
		assert(type(monsterKey) == "string" and monsterKey ~= "", "出生点 MonsterKey 无效")
	end

	table.freeze(definition.MonsterKeyByLevel)
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
	return if definition then definition.MonsterKeyByLevel[level] else nil
end

function MonsterSpawnPointCatalog.GetAll(): { Definition }
	return table.clone(sortedDefinitions)
end

return MonsterSpawnPointCatalog
