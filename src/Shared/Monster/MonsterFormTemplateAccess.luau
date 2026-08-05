--[[
	职责：按 P1～P5 的 Start/End 合同解析单形态实际模板和当前等级缩放。
	输入：模板根路径、FormIndex、0～1 的成长进度。
	输出：Start Model、应用到其 Clone 的绝对 Scale，或稳定失败原因。
	内部算法：读取 <Root>/P<Form>/Start 与 End，以两者包围盒高度比线性插值 Start 的 Scale。
	不负责：等级映射、克隆、放置、进化替换、生命或经济。

	路径合同：
	<Root>/P1/Start、<Root>/P1/End …… <Root>/P5/Start、<Root>/P5/End。
	Start 是实际运行模板；End 只提供该形态最后一级的目标尺寸。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InstancePath = require(ReplicatedStorage.Shared.InstancePath)

local MonsterFormTemplateAccess = {}

local function finitePositive(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value > 0
end

function MonsterFormTemplateAccess.Resolve(
	templateRoot: string,
	formIndex: number,
	growthAlpha: number
): (Model?, number?, string?)
	assert(type(templateRoot) == "string" and templateRoot ~= "", "templateRoot 必须是非空字符串")
	assert(type(formIndex) == "number" and formIndex >= 1 and formIndex % 1 == 0, "formIndex 必须是正整数")
	assert(
		type(growthAlpha) == "number"
			and growthAlpha == growthAlpha
			and growthAlpha >= 0
			and growthAlpha <= 1,
		"growthAlpha 必须在 0～1"
	)

	local formPath = string.format("%s/P%d", templateRoot, formIndex)
	local startTemplate = InstancePath.Find(formPath .. "/Start")
	local endTemplate = InstancePath.Find(formPath .. "/End")
	if not startTemplate or not startTemplate:IsA("Model") then
		return nil, nil, "StartTemplateUnavailable"
	end
	if not endTemplate or not endTemplate:IsA("Model") then
		return nil, nil, "EndTemplateUnavailable"
	end
	if not startTemplate.PrimaryPart then
		return nil, nil, "StartTemplateMissingPrimaryPart"
	end

	local startHeight = startTemplate:GetExtentsSize().Y
	local endHeight = endTemplate:GetExtentsSize().Y
	local startScale = startTemplate:GetScale()
	if not finitePositive(startHeight) then
		return nil, nil, "StartTemplateHeightInvalid"
	end
	if not finitePositive(endHeight) then
		return nil, nil, "EndTemplateHeightInvalid"
	end
	if not finitePositive(startScale) then
		return nil, nil, "StartTemplateScaleInvalid"
	end

	local endScale = startScale * endHeight / startHeight
	return startTemplate, startScale + (endScale - startScale) * growthAlpha, nil
end

return table.freeze(MonsterFormTemplateAccess)
