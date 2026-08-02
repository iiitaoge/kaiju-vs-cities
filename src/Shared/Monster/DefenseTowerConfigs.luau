--[[
	职责：定义 DefenseTowerConfigId 对应的射程、伤害和攻击间隔。
	输入：Get 接收非空 ConfigId。
	输出：不可变塔数值或 nil。
	不负责：塔实例、玩家状态、目标选择、冷却或伤害结算。
]]

local DefenseTowerConfigs = {}

local definitions = {
	D1BasicL1 = {
		Range = 45,
		Damage = 10,
		AttackInterval = 1,
	},
}

for configId, definition in definitions do
	assert(type(configId) == "string" and configId ~= "", "防御塔 ConfigId 无效")
	assert(type(definition.Range) == "number" and definition.Range >= 0, "防御塔射程无效")
	assert(type(definition.Damage) == "number" and definition.Damage > 0, "防御塔伤害无效")
	assert(type(definition.AttackInterval) == "number" and definition.AttackInterval > 0, "防御塔间隔无效")
	table.freeze(definition)
end
table.freeze(definitions)

function DefenseTowerConfigs.Get(configId: string)
	return definitions[configId]
end

return table.freeze(DefenseTowerConfigs)
