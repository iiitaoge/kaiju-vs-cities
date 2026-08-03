--[[
	职责：判断一个 Instance 范围是否包含零件且所有零件均已锚定。
	输入：任意 Instance。
	输出：自身或后代至少有一个 BasePart 且全部 Anchored 时为 true，否则为 false。
	内部算法：先检查输入自身，再遍历全部后代；不读取其他模块或业务配置。
]]

local AnchoredPartRules = {}

function AnchoredPartRules.HasOnlyAnchoredParts(object: Instance): boolean
	assert(typeof(object) == "Instance", "object 必须是 Instance")

	local foundPart = false
	if object:IsA("BasePart") then
		foundPart = true
		if not object.Anchored then
			return false
		end
	end

	for _, descendant in object:GetDescendants() do
		if descendant:IsA("BasePart") then
			foundPart = true
			if not descendant.Anchored then
				return false
			end
		end
	end

	return foundPart
end

return table.freeze(AnchoredPartRules)
