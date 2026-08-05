--[[
	职责：定义 MonsterKey 对应的模型模板和基础生命。
	不负责：出生点、玩家状态、模型生成或升级判断。
]]

local MonsterLevelProgressionRules = require(script.Parent.MonsterLevelProgressionRules)
local MonsterProgressionConfigs = require(script.Parent.MonsterProgressionConfigs)

local MonsterCatalog = {}

export type Definition = {
	MonsterKey: string,
	ProgressionId: string,
	DisplayName: string,
	Level: number,
	FormIndex: number,
	FormLevel: number,
	GrowthAlpha: number,
	TemplateRoot: string,
	MaxHealth: number,
}

local definitions: { [string]: Definition } = {}
local monsterKeyByProgressionAndLevel: { [string]: { [number]: string } } = {}
local maxLevelByProgression: { [string]: number } = {}

for progressionId, config in pairs(MonsterProgressionConfigs) do
	local maxLevel = MonsterLevelProgressionRules.GetMaxLevel(
		config.LevelsPerForm,
		config.FormCount
	)
	local keysByLevel = {}
	for level = 1, maxLevel do
		local appearance = assert(MonsterLevelProgressionRules.ResolveAppearance(
			level,
			config.LevelsPerForm,
			config.FormCount
		))
		local monsterKey = MonsterLevelProgressionRules.MakeMonsterKey(config.MonsterKeyPrefix, level)
		definitions[monsterKey] = {
			MonsterKey = monsterKey,
			ProgressionId = progressionId,
			DisplayName = config.DisplayName,
			Level = level,
			FormIndex = appearance.FormIndex,
			FormLevel = appearance.FormLevel,
			GrowthAlpha = appearance.GrowthAlpha,
			TemplateRoot = config.TemplateRoot,
			MaxHealth = MonsterLevelProgressionRules.ScaleIntegerByStages(
				config.MaxHealthBase,
				config.MaxHealthGrowthStages,
				level
			),
		}
		keysByLevel[level] = monsterKey
	end
	monsterKeyByProgressionAndLevel[progressionId] = table.freeze(keysByLevel)
	maxLevelByProgression[progressionId] = maxLevel
end

local sortedDefinitions = {}
for monsterKey, definition in pairs(definitions) do
	assert(definition.MonsterKey == monsterKey, "MonsterKey 与配置键不一致：" .. monsterKey)
	assert(type(definition.TemplateRoot) == "string" and definition.TemplateRoot ~= "", "TemplateRoot 无效")
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

function MonsterCatalog.GetMonsterKey(progressionId: string, level: number): string?
	local keysByLevel = monsterKeyByProgressionAndLevel[progressionId]
	return if keysByLevel then keysByLevel[level] else nil
end

function MonsterCatalog.GetMaxLevel(progressionId: string): number?
	return maxLevelByProgression[progressionId]
end

-- 输入：升级前后的 MonsterKey。
-- 输出：两者实际 Start 模板是否变化；任一身份未知时返回 nil。
-- 内部算法：只比较目录中的 FormIndex，不读取 Instance；同形态升级只改变缩放。
function MonsterCatalog.HasTemplateChanged(
	previousMonsterKey: string,
	newMonsterKey: string
): boolean?
	local previousDefinition = definitions[previousMonsterKey]
	local newDefinition = definitions[newMonsterKey]
	if not previousDefinition or not newDefinition then
		return nil
	end
	return previousDefinition.TemplateRoot ~= newDefinition.TemplateRoot
		or previousDefinition.FormIndex ~= newDefinition.FormIndex
end

return MonsterCatalog
