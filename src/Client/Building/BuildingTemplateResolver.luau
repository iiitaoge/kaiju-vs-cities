--[[
	职责：按完整身份字段解析一个建筑等级模板。
	输入：ModelRoot、GroupName、VariantName、正整数 Level。
	输出：匹配的 Model；合同不满足时返回 nil。
	内部算法：从 DataModel 开始逐段遍历路径，再查找 group/variant/levelN。
	不负责：不读取玩家状态、不计算放置位置、不 Clone 模型。
]]

local BuildingTemplateResolver = {}

local function resolvePath(path: string): Instance?
	local current: Instance = game
	for segment in string.gmatch(path, "[^/]+") do
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end
	return current
end

function BuildingTemplateResolver.Resolve(
	modelRoot: string,
	groupName: string,
	variantName: string,
	level: number
): Model?
	if type(modelRoot) ~= "string"
		or type(groupName) ~= "string"
		or type(variantName) ~= "string"
		or type(level) ~= "number"
		or level < 1
		or level % 1 ~= 0
	then
		return nil
	end

	local root = resolvePath(modelRoot)
	local group = root and root:FindFirstChild(groupName)
	local variant = group and group:FindFirstChild(variantName)
	local template = variant and variant:FindFirstChild("level" .. level)
	return if template and template:IsA("Model") then template else nil
end

return BuildingTemplateResolver
