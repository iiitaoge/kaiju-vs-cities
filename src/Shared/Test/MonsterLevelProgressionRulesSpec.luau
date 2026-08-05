local Spec = {}

function Spec.Run(): boolean
	local MonsterLevelProgressionRules = require(
		script.Parent.Parent.Monster.MonsterLevelProgressionRules
	)

	local function expectAppearance(level: number, expectedForm: number, expectedFormLevel: number, expectedAlpha: number)
		local appearance = MonsterLevelProgressionRules.ResolveAppearance(level, 15, 5)
		assert(appearance ~= nil, string.format("等级 %d 没有映射", level))
		assert(appearance.FormIndex == expectedForm, string.format("等级 %d 形态错误", level))
		assert(appearance.FormLevel == expectedFormLevel, string.format("等级 %d 形态内等级错误", level))
		assert(math.abs(appearance.GrowthAlpha - expectedAlpha) < 1e-6, string.format("等级 %d 成长进度错误", level))
	end

	expectAppearance(1, 1, 1, 0)
	expectAppearance(15, 1, 15, 1)
	expectAppearance(16, 2, 1, 0)
	expectAppearance(30, 2, 15, 1)
	expectAppearance(61, 5, 1, 0)
	expectAppearance(75, 5, 15, 1)
	assert(MonsterLevelProgressionRules.ResolveAppearance(76, 15, 5) == nil, "封顶后不应继续映射")
	assert(MonsterLevelProgressionRules.GetMaxLevel(15, 5) == 75, "封顶等级错误")
	local staged = {
		{ UntilLevel = 3, Growth = 2 },
		{ UntilLevel = 5, Growth = 3 },
	}
	assert(
		MonsterLevelProgressionRules.ScaleIntegerByStages(10, staged, 1) == 10,
		"分段成长 Level 1 错误"
	)
	assert(
		MonsterLevelProgressionRules.ScaleIntegerByStages(10, staged, 3) == 40,
		"分段成长第一阶段错误"
	)
	assert(
		MonsterLevelProgressionRules.ScaleIntegerByStages(10, staged, 5) == 360,
		"分段成长跨阶段错误"
	)
	assert(MonsterLevelProgressionRules.MakeMonsterKey("Godzilla-L", 6) == "Godzilla-L006", "Key 不稳定")
	return true
end

return Spec
