local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ValueValidation = require(ReplicatedStorage.Shared.ValueValidation)

local ValueValidationSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "ValueValidationSpec: " .. message)
end

-- 输入：有限值、NaN、无穷、错误类型和字符串边界。
-- 输出：三个基础判定函数保持稳定语义时返回 true。
-- 内部算法：逐类覆盖有效、边界和错误类型，不读取业务配置或 Instance。
function ValueValidationSpec.Run(): boolean
	expect(ValueValidation.IsFiniteNumber(0), "0 应为有限数")
	expect(ValueValidation.IsFiniteNumber(-1e30), "有限负数被拒绝")
	expect(not ValueValidation.IsFiniteNumber(0 / 0), "NaN 被接受")
	expect(not ValueValidation.IsFiniteNumber(math.huge), "正无穷被接受")
	expect(not ValueValidation.IsFiniteNumber(-math.huge), "负无穷被接受")
	expect(not ValueValidation.IsFiniteNumber("1"), "字符串被当作有限数")

	expect(ValueValidation.IsFiniteVector3(Vector3.new(1, -2, 3)), "有限 Vector3 被拒绝")
	expect(
		not ValueValidation.IsFiniteVector3(Vector3.new(math.huge, 0, 0)),
		"含无穷分量的 Vector3 被接受"
	)
	expect(
		not ValueValidation.IsFiniteVector3(Vector3.new(0 / 0, 0, 0)),
		"含 NaN 分量的 Vector3 被接受"
	)
	expect(not ValueValidation.IsFiniteVector3(CFrame.new()), "非 Vector3 被接受")

	expect(ValueValidation.IsNonEmptyString("value"), "非空字符串被拒绝")
	expect(ValueValidation.IsNonEmptyString(" "), "空白字符串应保持非空语义")
	expect(not ValueValidation.IsNonEmptyString(""), "空字符串被接受")
	expect(not ValueValidation.IsNonEmptyString(nil), "nil 被接受为字符串")
	expect(table.isfrozen(ValueValidation), "基础值校验模块必须只读")
	return true
end

return ValueValidationSpec
