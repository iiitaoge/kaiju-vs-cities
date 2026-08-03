local Spec = {}

function Spec.Run(): boolean
	local MonsterLevelProgressionRules = require(
		script.Parent.Parent.Monster.MonsterLevelProgressionRules
	)

	local function expectAppearance(level: number, expectedForm: number, expectedVisual: number)
		local appearance = MonsterLevelProgressionRules.ResolveAppearance(level, 5, 3, 5)
		assert(appearance ~= nil, string.format("等级 %d 没有映射", level))
		assert(appearance.FormIndex == expectedForm, string.format("等级 %d 形态错误", level))
		assert(appearance.VisualLevel == expectedVisual, string.format("等级 %d 外观等级错误", level))
	end

	expectAppearance(1, 1, 1)
	expectAppearance(5, 1, 1)
	expectAppearance(6, 1, 2)
	expectAppearance(10, 1, 2)
	expectAppearance(11, 1, 3)
	expectAppearance(15, 1, 3)
	expectAppearance(16, 2, 1)
	expectAppearance(75, 5, 3)
	assert(MonsterLevelProgressionRules.ResolveAppearance(76, 5, 3, 5) == nil, "封顶后不应继续映射")
	assert(MonsterLevelProgressionRules.GetMaxLevel(5, 3, 5) == 75, "封顶等级错误")
	assert(MonsterLevelProgressionRules.MakeMonsterKey("Godzilla-L", 6) == "Godzilla-L006", "Key 不稳定")
	return true
end

return Spec
