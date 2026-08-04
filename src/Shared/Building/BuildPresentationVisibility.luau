--[[
	职责：统一管理服务器权威模型在建造表现期间的初始隐藏和最终恢复。
	输入：尚未进入可见世界的 Model，或此前由 Hide 隐藏的 Model。
	输出：Hide / Restore 返回是否改变状态；ResolveTransparency 返回表现结束后的透明度。
	内部算法：把 BasePart、Decal、Texture 的原透明度暂存在各自 Attribute，先设为完全透明，
		再由协调器正常 Parent；表现结束后恢复原值并清理临时 Attribute。
	不负责：Parent、Clone、动画时长、客户端 Tween、业务状态或模型选择。
]]

local BuildPresentationVisibility = {}

local HIDDEN_ATTRIBUTE = "BuildPresentationHidden"
local ORIGINAL_TRANSPARENCY_ATTRIBUTE = "BuildPresentationOriginalTransparency"

local function isTransparencyVisual(instance: Instance): boolean
	return instance:IsA("BasePart")
		or instance:IsA("Decal")
		or instance:IsA("Texture")
end

function BuildPresentationVisibility.IsHidden(model: Model): boolean
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	return model:GetAttribute(HIDDEN_ATTRIBUTE) == true
end

function BuildPresentationVisibility.ResolveTransparency(instance: Instance): number
	assert(
		typeof(instance) == "Instance" and isTransparencyVisual(instance),
		"instance 必须是 BasePart、Decal 或 Texture"
	)
	local original = instance:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE)
	return if type(original) == "number" then original else (instance :: any).Transparency
end

function BuildPresentationVisibility.Hide(model: Model): boolean
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	if BuildPresentationVisibility.IsHidden(model) then
		return false
	end

	for _, descendant in model:GetDescendants() do
		if isTransparencyVisual(descendant) then
			local visual = descendant :: any
			visual:SetAttribute(
				ORIGINAL_TRANSPARENCY_ATTRIBUTE,
				visual.Transparency
			)
			visual.Transparency = 1
		end
	end
	model:SetAttribute(HIDDEN_ATTRIBUTE, true)
	return true
end

function BuildPresentationVisibility.Restore(model: Model): boolean
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	if not BuildPresentationVisibility.IsHidden(model) then
		return false
	end

	for _, descendant in model:GetDescendants() do
		if isTransparencyVisual(descendant) then
			local original = descendant:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE)
			if type(original) == "number" then
				(descendant :: any).Transparency = original
				descendant:SetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE, nil)
			end
		end
	end
	model:SetAttribute(HIDDEN_ATTRIBUTE, nil)
	return true
end

return table.freeze(BuildPresentationVisibility)
