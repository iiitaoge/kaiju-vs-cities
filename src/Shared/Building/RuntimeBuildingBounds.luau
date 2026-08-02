--[[
	职责：从当前服务器运行时建筑计算实际空间边界。
	输入：一个仍在数据树中的 Model。
	输出：CFrame、Size；没有 BasePart 或输入无效时返回 nil 和原因。
	内部算法：验证至少一个 BasePart 后调用 Model:GetBoundingBox。
	不负责：不解析模板、不查找 Slot、不验证玩家归属。
]]

local RuntimeBuildingBounds = {}

export type Target = {
	CFrame: CFrame,
	Size: Vector3,
}

function RuntimeBuildingBounds.Resolve(model: Model): (Target?, string?)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil, "BuildingNotModel"
	end
	if not model.Parent then
		return nil, "BuildingUnavailable"
	end

	local hasPart = false
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			hasPart = true
			break
		end
	end
	if not hasPart then
		return nil, "BuildingHasNoParts"
	end

	local boundingCFrame, boundingSize = model:GetBoundingBox()
	return {
		CFrame = boundingCFrame,
		Size = boundingSize,
	}, nil
end

return RuntimeBuildingBounds
