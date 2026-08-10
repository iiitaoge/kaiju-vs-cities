--[[
	职责：提供七日奖励的可编辑内容配置。
	输入：无；策划只需要修改 Days 中每一天的 Type 和 Amount。
	输出：七个有序奖励、24 小时冷却时间和货币类型白名单。
	内部算法：无；初始化并冻结纯配置表。
	不负责：判断是否可领取、修改玩家余额、存档、Remote 或 UI。
]]

local CurrencyProtocol = require(script.Parent.Parent.Economy.CurrencyProtocol)

local types = CurrencyProtocol.Types

-- 回流配置：金币奖励用于阶段追赶，钻石奖励用于载具成长；Day 1 由程序在教程完成后展示。
local days = {
	[1] = { Day = 1, Type = types.Money, Amount = 1_000 },
	[2] = { Day = 2, Type = types.Diamond, Amount = 100 },
	[3] = { Day = 3, Type = types.Money, Amount = 50_000 },
	[4] = { Day = 4, Type = types.Diamond, Amount = 300 },
	[5] = { Day = 5, Type = types.Money, Amount = 500_000 },
	[6] = { Day = 6, Type = types.Diamond, Amount = 800 },
	[7] = { Day = 7, Type = types.Money, Amount = 5_000_000 },
}

for _, reward in days do
	table.freeze(reward)
end

return table.freeze({
	CooldownSeconds = 24 * 60 * 60,
	TotalDays = 7,
	CurrencyTypes = types,
	Days = table.freeze(days),
})
