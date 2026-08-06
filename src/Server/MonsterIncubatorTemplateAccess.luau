--[[
	职责：从显式模板目录解析并验证一个罐体模板。
	输入：模板根 Folder、TemplateId。
	输出：包含 Base/MonsterHomeAttachment、Liquid(Model/BasePart)、Glass、Target 的唯一 Model，或稳定失败原因。
	内部算法：只检查直接子级、类型、可克隆性和全部零件锚定状态。
	不负责：读取配置、查找 Plot、Clone、定位、动画或怪兽生成。
]]

local AnchoredPartRules = require(script.Parent.AnchoredPartRules)
local UniqueNamedChildAccess = require(script.Parent.UniqueNamedChildAccess)

local MonsterIncubatorTemplateAccess = {}

function MonsterIncubatorTemplateAccess.Resolve(
	templateRoot: Folder,
	templateId: string
): (Model?, string?)
	if typeof(templateRoot) ~= "Instance" or not templateRoot:IsA("Folder") then
		return nil, "InvalidIncubatorTemplateRoot"
	end
	if type(templateId) ~= "string" or templateId == "" then
		return nil, "InvalidIncubatorTemplateId"
	end

	local template, templateDuplicated = UniqueNamedChildAccess.Find(
		templateRoot,
		templateId
	)
	if templateDuplicated then
		return nil, "DuplicateIncubatorTemplate"
	end
	if not template or not template:IsA("Model") then
		return nil, "MissingIncubatorTemplate"
	end
	if not template.Archivable then
		return nil, "IncubatorTemplateNotArchivable"
	end

	local base, baseDuplicated = UniqueNamedChildAccess.Find(template, "Base")
	if baseDuplicated then
		return nil, "DuplicateBase"
	end
	local liquid, liquidDuplicated = UniqueNamedChildAccess.Find(template, "Liquid")
	if liquidDuplicated then
		return nil, "DuplicateLiquid"
	end
	local glass, glassDuplicated = UniqueNamedChildAccess.Find(template, "Glass")
	if glassDuplicated then
		return nil, "DuplicateGlass"
	end
	local target, targetDuplicated = UniqueNamedChildAccess.Find(template, "Target")
	if targetDuplicated then
		return nil, "DuplicateTarget"
	end
	if not base or not base:IsA("Model") then
		return nil, "InvalidIncubatorTemplateBase"
	end
	local monsterHome, monsterHomeDuplicated = UniqueNamedChildAccess.Find(
		base,
		"MonsterHomeAttachment"
	)
	if monsterHomeDuplicated then
		return nil, "DuplicateMonsterHomeAttachment"
	end
	if not monsterHome or not monsterHome:IsA("Attachment") then
		return nil, "InvalidMonsterHomeAttachment"
	end
	if not liquid or (not liquid:IsA("BasePart") and not liquid:IsA("Model")) then
		return nil, "InvalidIncubatorTemplateLiquid"
	end
	if not glass or not glass:IsA("BasePart") then
		return nil, "InvalidIncubatorTemplateGlass"
	end
	if not target or not target:IsA("BasePart") then
		return nil, "InvalidIncubatorTemplateTarget"
	end
	if not AnchoredPartRules.HasOnlyAnchoredParts(template) then
		return nil, "IncubatorTemplateMustBeAnchored"
	end

	return template, nil
end

return MonsterIncubatorTemplateAccess
