--[[
	职责：定义每个收入区域唯一防守怪兽的稳定身份和场景定位约定。
	输入：DefenseSpawnPointId、RegionId 或等级。
	输出：不可变目录定义或与攻击怪兽共用成长线的 MonsterKey。
	内部算法：R1～R6 一区一只，场景均使用区域直接子级 DefenseMonsterSlot。
	不负责：读取 Workspace、区域解锁、模型生成、升级或复活。
]]

local MonsterCatalog = require(script.Parent.MonsterCatalog)

local DefenseMonsterSlotCatalog = {}

export type Definition = {
	SpawnPointId: string,
	RegionId: string,
	SlotName: string,
	ProgressionId: string,
}

local definitionsById: { [string]: Definition } = {}
local definitionsByRegion: { [string]: Definition } = {}
local sortedDefinitions = {}

for index = 1, 6 do
	local regionId = "R" .. index
	local spawnPointId = "DM-" .. regionId
	local definition = table.freeze({
		SpawnPointId = spawnPointId,
		RegionId = regionId,
		SlotName = "DefenseMonsterSlot",
		ProgressionId = "Godzilla",
	})
	assert(MonsterCatalog.GetMonsterKey(definition.ProgressionId, 1), regionId .. " 缺少怪兽成长线")
	definitionsById[spawnPointId] = definition
	definitionsByRegion[regionId] = definition
	table.insert(sortedDefinitions, definition)
end

table.freeze(definitionsById)
table.freeze(definitionsByRegion)
table.freeze(sortedDefinitions)

function DefenseMonsterSlotCatalog.Get(spawnPointId: string): Definition?
	return definitionsById[spawnPointId]
end

function DefenseMonsterSlotCatalog.GetByRegion(regionId: string): Definition?
	return definitionsByRegion[regionId]
end

function DefenseMonsterSlotCatalog.GetMonsterKey(spawnPointId: string, level: number): string?
	local definition = definitionsById[spawnPointId]
	return if definition then MonsterCatalog.GetMonsterKey(definition.ProgressionId, level) else nil
end

function DefenseMonsterSlotCatalog.GetMaxLevel(spawnPointId: string): number?
	local definition = definitionsById[spawnPointId]
	return if definition then MonsterCatalog.GetMaxLevel(definition.ProgressionId) else nil
end

function DefenseMonsterSlotCatalog.GetAll(): { Definition }
	return table.clone(sortedDefinitions)
end

return DefenseMonsterSlotCatalog
