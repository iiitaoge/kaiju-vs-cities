-- 验证 R4 使用的“逐级建造、每两级换模型、模板封顶”纯规则。
local IncomeBuildingProgressionRules = require(
	script.Parent.Parent.Building.IncomeBuildingProgressionRules
)

local Spec = {}

function Spec.Run(): boolean
	local resolve = IncomeBuildingProgressionRules.ResolveModelLevel
	assert(resolve(1, 2, 2, 3) == nil, "未到建造等级时应返回 nil")
	assert(resolve(2, 2, 2, 3) == 1, "区域 2 级应使用模型 1 级")
	assert(resolve(3, 2, 2, 3) == 2, "区域 3 级应使用模型 2 级")
	assert(resolve(6, 2, 2, 3) == 3, "区域 6 级应使用模型 3 级")
	assert(resolve(8, 2, 2, 3) == 3, "Waste 模型应封顶在 3 级")
	assert(resolve(8, 1, 2, 4) == 4, "Warehouse 模型应封顶在 4 级")
	assert(resolve(1, 1, 2, 3) == 1, "R5 首次建造应使用模型 1 级")
	assert(resolve(2, 1, 2, 3) == 1, "R5 区域 2 级仍应使用模型 1 级")
	assert(resolve(3, 1, 2, 3) == 2, "R5 区域 3 级应使用模型 2 级")
	assert(resolve(5, 1, 2, 3) == 3, "R5 区域 5 级应使用模型 3 级")
	assert(resolve(3, 1, 1, nil) == 3, "旧区域应保持区域等级等于模型等级")
	return true
end

return Spec
