local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneyCheatCommandRules = require(
	ReplicatedStorage.Shared.Cheat.MoneyCheatCommandRules
)

local MoneyCheatCommandRulesSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "MoneyCheatCommandRulesSpec: " .. message)
end

-- 输入：合法金额、空格变体、错误格式与数值边界。
-- 输出：仅严格合法的 /money 指令返回非负整数。
-- 内部算法：逐类覆盖语法与有限数校验，不访问玩家或现金状态。
function MoneyCheatCommandRulesSpec.Run(): boolean
	expect(MoneyCheatCommandRules.ParseAmount("/money 0") == 0, "应接受零")
	expect(MoneyCheatCommandRules.ParseAmount("/money 1000") == 1000, "金额解析错误")
	expect(MoneyCheatCommandRules.ParseAmount("/money   007  ") == 7, "空格解析错误")

	for _, message in {
		"/money",
		"/money -1",
		"/money +1",
		"/money 1.5",
		"/money 1e3",
		"/money 10 extra",
		"/Money 10",
		"money 10",
		"/money " .. string.rep("9", 400),
	} do
		expect(MoneyCheatCommandRules.ParseAmount(message) == nil, "错误接受：" .. message)
	end

	expect(MoneyCheatCommandRules.ParseAmount(nil) == nil, "nil 被接受")
	expect(table.isfrozen(MoneyCheatCommandRules), "规则模块必须只读")
	return true
end

return MoneyCheatCommandRulesSpec
