--[[
	职责：提供七日奖励的可编辑内容配置。
	输入：无；策划只需要修改 Days 中每一天的 Type 和 Amount。
	输出：七个有序奖励、24 小时冷却时间和货币类型白名单。
	内部算法：无；初始化并冻结纯配置表。
	不负责：判断是否可领取、修改玩家余额、存档、Remote 或 UI。
]]

local CurrencyProtocol = require(script.Parent.Parent.Economy.CurrencyProtocol)

local types = CurrencyProtocol.Types

-- 测试配置：前四天发钱，后三天发钻石；同种货币按固定步长递进。
local days = {
	[1] = { Day = 1, Type = types.Money, Amount = 30000 },
	[2] = { Day = 2, Type = types.Money, Amount = 60000 },
	[3] = { Day = 3, Type = types.Money, Amount = 90000 },
	[4] = { Day = 4, Type = types.Money, Amount = 120000 },
	[5] = { Day = 5, Type = types.Diamond, Amount = 500 },
	[6] = { Day = 6, Type = types.Diamond, Amount = 4000 },
	[7] = { Day = 7, Type = types.Diamond, Amount = 10000 },
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
