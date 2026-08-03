--[[
	职责：提供不含业务语义的基础 Luau / Roblox 值判定。
	输入：任意值。
	输出：值是否为有限 number、有限 Vector3 或非空 string。
	内部算法：检查运行时类型，并排除 NaN、正负无穷和空字符串。
	不负责：正负范围、整数、ID、配置或错误原因。
]]

local ValueValidation = {}

function ValueValidation.IsFiniteNumber(value): boolean
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

function ValueValidation.IsFiniteVector3(value): boolean
	return typeof(value) == "Vector3"
		and ValueValidation.IsFiniteNumber(value.X)
		and ValueValidation.IsFiniteNumber(value.Y)
		and ValueValidation.IsFiniteNumber(value.Z)
end

function ValueValidation.IsNonEmptyString(value): boolean
	return type(value) == "string" and value ~= ""
end

return table.freeze(ValueValidation)
