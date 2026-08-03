local ServerScriptService = game:GetService("ServerScriptService")

local AnchoredPartRules = require(ServerScriptService.Server.AnchoredPartRules)
local UniqueNamedChildAccess = require(ServerScriptService.Server.UniqueNamedChildAccess)

local ServerUtilityModulesSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "ServerUtilityModulesSpec: " .. message)
end

local function testAnchoredPartRules()
	local root = Instance.new("Folder")
	local succeeded, message = xpcall(function()
		expect(not AnchoredPartRules.HasOnlyAnchoredParts(root), "空容器不应通过锚定校验")

		local directPart = Instance.new("Part")
		directPart.Anchored = true
		directPart.Parent = root
		expect(AnchoredPartRules.HasOnlyAnchoredParts(root), "锚定直接子级被拒绝")

		local nested = Instance.new("Folder")
		nested.Parent = root
		local nestedPart = Instance.new("Part")
		nestedPart.Anchored = true
		nestedPart.Parent = nested
		expect(AnchoredPartRules.HasOnlyAnchoredParts(root), "锚定嵌套子级被拒绝")

		nestedPart.Anchored = false
		expect(not AnchoredPartRules.HasOnlyAnchoredParts(root), "未锚定后代被接受")
		expect(AnchoredPartRules.HasOnlyAnchoredParts(directPart), "锚定根 BasePart 被拒绝")
		directPart.Anchored = false
		expect(not AnchoredPartRules.HasOnlyAnchoredParts(directPart), "未锚定根 BasePart 被接受")
		expect(not pcall(AnchoredPartRules.HasOnlyAnchoredParts, "invalid"), "错误输入未断言")
		expect(table.isfrozen(AnchoredPartRules), "锚定规则模块必须只读")
	end, debug.traceback)
	root:Destroy()
	assert(succeeded, message)
end

local function testUniqueNamedChildAccess()
	local root = Instance.new("Folder")
	local succeeded, message = xpcall(function()
		local missing, missingDuplicated = UniqueNamedChildAccess.Find(root, "Target")
		expect(missing == nil and not missingDuplicated, "缺失子级结果错误")

		local nested = Instance.new("Folder")
		nested.Parent = root
		local nestedTarget = Instance.new("Part")
		nestedTarget.Name = "Target"
		nestedTarget.Parent = nested
		local recursive, recursiveDuplicated = UniqueNamedChildAccess.Find(root, "Target")
		expect(recursive == nil and not recursiveDuplicated, "不应递归命中后代")

		local first = Instance.new("Part")
		first.Name = "Target"
		first.Parent = root
		local unique, uniqueDuplicated = UniqueNamedChildAccess.Find(root, "Target")
		expect(unique == first and not uniqueDuplicated, "唯一直接子级解析错误")

		local second = Instance.new("Folder")
		second.Name = "Target"
		second.Parent = root
		local duplicate, duplicated = UniqueNamedChildAccess.Find(root, "Target")
		expect(duplicate == nil and duplicated, "重复同名直接子级未被报告")

		second:Destroy()
		local restored, restoredDuplicated = UniqueNamedChildAccess.Find(root, "Target")
		expect(restored == first and not restoredDuplicated, "删除重复项后未恢复唯一结果")
		expect(not pcall(UniqueNamedChildAccess.Find, "invalid", "Target"), "错误 parent 未断言")
		expect(not pcall(UniqueNamedChildAccess.Find, root, ""), "空名称未断言")
		expect(table.isfrozen(UniqueNamedChildAccess), "唯一子级模块必须只读")
	end, debug.traceback)
	root:Destroy()
	assert(succeeded, message)
end

-- 输入：临时 Instance 树和非法参数。
-- 输出：两个无依赖服务器小模块满足边界合同时返回 true。
-- 内部算法：覆盖根/后代锚定状态，以及缺失/唯一/重复/非递归名称查找。
function ServerUtilityModulesSpec.Run(): boolean
	testAnchoredPartRules()
	testUniqueNamedChildAccess()
	return true
end

return ServerUtilityModulesSpec
