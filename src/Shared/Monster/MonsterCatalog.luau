--[[
	职责：定义 MonsterKey 对应的模型模板和基础生命。
	不负责：出生点、玩家状态、模型生成或升级判断。
]]

local MonsterCatalog = {}

export type Definition = {
	MonsterKey: string,
	TemplatePath: string,
	MaxHealth: number,
}

local definitions: { [string]: Definition } = {
	P1 = {
		MonsterKey = "P1",
		TemplatePath = "ReplicatedStorage/Godzilla/P1",
		MaxHealth = 100,
	},
	P4 = {
		MonsterKey = "P4",
		TemplatePath = "ReplicatedStorage/Godzilla/P4",
		MaxHealth = 100,
	},
}

local sortedDefinitions = {}
for monsterKey, definition in pairs(definitions) do
	assert(definition.MonsterKey == monsterKey, "MonsterKey 与配置键不一致：" .. monsterKey)
	assert(type(definition.TemplatePath) == "string" and definition.TemplatePath ~= "", "TemplatePath 无效")
	assert(
		type(definition.MaxHealth) == "number"
			and definition.MaxHealth == definition.MaxHealth
			and definition.MaxHealth < math.huge
			and definition.MaxHealth > 0,
		"MaxHealth 必须是有限正数"
	)
	table.freeze(definition)
	table.insert(sortedDefinitions, definition)
end

table.sort(sortedDefinitions, function(a, b)
	return a.MonsterKey < b.MonsterKey
end)
table.freeze(sortedDefinitions)
table.freeze(definitions)

function MonsterCatalog.Get(monsterKey: string): Definition?
	return definitions[monsterKey]
end

function MonsterCatalog.GetAll(): { Definition }
	return table.clone(sortedDefinitions)
end

return MonsterCatalog
