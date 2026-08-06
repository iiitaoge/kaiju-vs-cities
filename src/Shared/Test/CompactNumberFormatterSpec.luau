local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CompactNumberFormatter = require(
	ReplicatedStorage.Shared.UI.CompactNumberFormatter
)

local CompactNumberFormatterSpec = {}

function CompactNumberFormatterSpec.Run(): boolean
	assert(CompactNumberFormatter.Format(0) == "0", "零格式错误")
	assert(CompactNumberFormatter.Format(12.5) == "12.5", "小数格式错误")
	assert(CompactNumberFormatter.Format(999) == "999", "普通整数格式错误")
	assert(CompactNumberFormatter.Format(1_250) == "1.25K", "K 后缀格式错误")
	assert(CompactNumberFormatter.Format(1_210_000) == "1.21M", "M 后缀格式错误")
	assert(CompactNumberFormatter.Format(2_500_000_000) == "2.5B", "B 后缀格式错误")
	assert(CompactNumberFormatter.Format(1_250_000_000) == "1.25B", "B 后缀格式错误")
	assert(table.isfrozen(CompactNumberFormatter), "格式化模块必须只读")
	return true
end

return CompactNumberFormatterSpec
