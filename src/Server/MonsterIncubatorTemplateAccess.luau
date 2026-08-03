--[[
	职责：从显式模板目录解析并验证一个罐体模板。
	输入：模板根 Folder、TemplateId。
	输出：包含 Base/Liquid/Glass/Target 的唯一 Model，或稳定失败原因。
	内部算法：只检查直接子级、类型、可克隆性和全部零件锚定状态。
	不负责：读取配置、查找 Plot、Clone、定位、动画或怪兽生成。
]]

local MonsterIncubatorTemplateAccess = {}

local function findUniqueChild(parent: Instance, name: string): (Instance?, string?)
	local found = nil
	for _, child in parent:GetChildren() do
		if child.Name == name then
			if found then
				return nil, "Duplicate" .. name
			end
			found = child
		end
	end
	return found, nil
end

local function allPartsAnchored(model: Model): boolean
	local foundPart = false
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			foundPart = true
			if not descendant.Anchored then
				return false
			end
		end
	end
	return foundPart
end

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

	local template, duplicateReason = findUniqueChild(templateRoot, templateId)
	if duplicateReason then
		return nil, "DuplicateIncubatorTemplate"
	end
	if not template or not template:IsA("Model") then
		return nil, "MissingIncubatorTemplate"
	end
	if not template.Archivable then
		return nil, "IncubatorTemplateNotArchivable"
	end

	local base, baseReason = findUniqueChild(template, "Base")
	local liquid, liquidReason = findUniqueChild(template, "Liquid")
	local glass, glassReason = findUniqueChild(template, "Glass")
	local target, targetReason = findUniqueChild(template, "Target")
	local childReason = baseReason or liquidReason or glassReason or targetReason
	if childReason then
		return nil, childReason
	end
	if not base or not base:IsA("Model") then
		return nil, "InvalidIncubatorTemplateBase"
	end
	if not liquid or not liquid:IsA("BasePart") then
		return nil, "InvalidIncubatorTemplateLiquid"
	end
	if not glass or not glass:IsA("BasePart") then
		return nil, "InvalidIncubatorTemplateGlass"
	end
	if not target or not target:IsA("BasePart") then
		return nil, "InvalidIncubatorTemplateTarget"
	end
	if not allPartsAnchored(template) then
		return nil, "IncubatorTemplateMustBeAnchored"
	end

	return template, nil
end

return MonsterIncubatorTemplateAccess
