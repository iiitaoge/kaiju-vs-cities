--[[
	输入：MonsterKey。
	输出：怪兽模板、怪兽定义；失败时返回稳定原因。
	内部算法：从 MonsterCatalog 读取路径，再通过 InstancePath 获取并验证 Model。
	不负责：克隆、放置、状态或容量。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)

local MonsterTemplateResolver = {}

function MonsterTemplateResolver.Resolve(monsterKey: string)
	local definition = MonsterCatalog.Get(monsterKey)
	if not definition then
		return nil, nil, "UnknownMonsterKey"
	end

	local succeeded, instanceOrError = pcall(InstancePath.Get, definition.TemplatePath)
	if not succeeded then
		warn(string.format("怪兽模板不可用：%s (%s)", monsterKey, tostring(instanceOrError)))
		return nil, definition, "MonsterTemplateUnavailable"
	end
	if not instanceOrError:IsA("Model") then
		return nil, definition, "MonsterTemplateNotModel"
	end
	return instanceOrError, definition, nil
end

return MonsterTemplateResolver
