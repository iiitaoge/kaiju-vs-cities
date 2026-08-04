--[[
	职责：把有限数值格式化为世界 UI 使用的紧凑文本。
	输入：有限 number。
	输出：最多两位小数的普通数字，或 K/M/B/T/Qa/Qi 后缀文本。
	内部算法：按绝对值选择最大后缀，再根据量级保留 0～2 位小数。
	不负责：货币图标、正负号语义或 UI 实例。
]]

local CompactNumberFormatter = {}

local suffixes = {
	{ Threshold = 1e18, Suffix = "Qi" },
	{ Threshold = 1e15, Suffix = "Qa" },
	{ Threshold = 1e12, Suffix = "T" },
	{ Threshold = 1e9, Suffix = "B" },
	{ Threshold = 1e6, Suffix = "M" },
	{ Threshold = 1e3, Suffix = "K" },
}

local function trim(text: string): string
	return (text:gsub("(%..-)0+$", "%1"):gsub("%.$", ""))
end

local function decimalsFor(value: number): number
	local magnitude = math.abs(value)
	if magnitude >= 100 then
		return 0
	end
	if magnitude >= 10 then
		return 1
	end
	return 2
end

function CompactNumberFormatter.Format(value: number): string
	assert(
		type(value) == "number" and value == value and math.abs(value) < math.huge,
		"value 必须是有限 number"
	)

	for _, entry in suffixes do
		if math.abs(value) >= entry.Threshold then
			local scaled = value / entry.Threshold
			local text = string.format("%." .. decimalsFor(scaled) .. "f", scaled)
			return trim(text) .. entry.Suffix
		end
	end

	local rounded = math.round(value)
	if math.abs(value - rounded) < 1e-6 then
		return tostring(rounded)
	end
	return trim(string.format("%.2f", value))
end

return table.freeze(CompactNumberFormatter)
