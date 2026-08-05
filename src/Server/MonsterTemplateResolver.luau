--[[
	输入：MonsterKey。
	输出：怪兽 Start 模板、怪兽定义、当前等级绝对缩放；失败时返回稳定原因。
	内部算法：从 MonsterCatalog 读取形态与成长进度，再按 P/Start/End 合同解析。
	不负责：克隆、放置、状态或容量。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local MonsterFormTemplateAccess = require(
	ReplicatedStorage.Shared.Monster.MonsterFormTemplateAccess
)

local MonsterTemplateResolver = {}

function MonsterTemplateResolver.Resolve(monsterKey: string)
	local definition = MonsterCatalog.Get(monsterKey)
	if not definition then
		return nil, nil, nil, "UnknownMonsterKey"
	end

	local template, modelScale, reason = MonsterFormTemplateAccess.Resolve(
		definition.TemplateRoot,
		definition.FormIndex,
		definition.GrowthAlpha
	)
	if not template or not modelScale then
		return nil, definition, nil, reason or "MonsterTemplateUnavailable"
	end
	return template, definition, modelScale, nil
end

return MonsterTemplateResolver
