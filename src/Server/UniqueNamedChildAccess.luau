--[[
	职责：在一个 Instance 的直接子级中按名称查找唯一对象。
	输入：父 Instance 和非空子级名称。
	输出：零或一个匹配子级，以及是否存在同名重复对象。
	内部算法：单次遍历直接子级；发现第二个同名对象时立即报告重复。
	不负责：递归查找、类型验证、业务错误码或修改 Instance。
]]

local UniqueNamedChildAccess = {}

function UniqueNamedChildAccess.Find(
	parent: Instance,
	name: string
): (Instance?, boolean)
	assert(typeof(parent) == "Instance", "parent 必须是 Instance")
	assert(type(name) == "string" and name ~= "", "name 必须是非空字符串")

	local found = nil
	for _, child in parent:GetChildren() do
		if child.Name == name then
			if found then
				return nil, true
			end
			found = child
		end
	end
	return found, false
end

return table.freeze(UniqueNamedChildAccess)
