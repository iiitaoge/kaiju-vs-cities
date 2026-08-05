--[[
	职责：按共用 MonsterKey 外观映射解析 ReplicatedStorage.DefenseGodzilla 模板。
	输入：MonsterKey。
	输出：防守 Start Model、共用怪兽定义、当前等级绝对缩放或稳定失败原因。
	不负责：克隆、放置、战斗数值或升级。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local MonsterFormTemplateAccess = require(
	ReplicatedStorage.Shared.Monster.MonsterFormTemplateAccess
)

local DefenseMonsterTemplateResolver = {}

function DefenseMonsterTemplateResolver.Resolve(monsterKey: string)
	local definition = MonsterCatalog.Get(monsterKey)
	if not definition then
		return nil, nil, nil, "UnknownMonsterKey"
	end
	local template, modelScale, reason = MonsterFormTemplateAccess.Resolve(
		"ReplicatedStorage/DefenseGodzilla",
		definition.FormIndex,
		definition.GrowthAlpha
	)
	if not template or not modelScale then
		return nil, definition, nil, reason or "DefenseMonsterTemplateUnavailable"
	end
	return template, definition, modelScale, nil
end

return DefenseMonsterTemplateResolver
