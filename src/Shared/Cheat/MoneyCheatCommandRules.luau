--[[
	职责：解析增加玩家现金的作弊聊天指令。
	输入：完整聊天文本，格式为 /money <非负十进制整数>。
	输出：合法时返回待增加的金额；非法时返回 nil。
	内部算法：严格匹配指令与十进制数字，再排除无法表示为有限整数的数值。
	不负责：Studio 权限、玩家查找、余额写入或聊天反馈。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ValueValidation = require(ReplicatedStorage.Shared.ValueValidation)

local MoneyCheatCommandRules = {}

function MoneyCheatCommandRules.ParseAmount(message): number?
	if type(message) ~= "string" then
		return nil
	end

	local amountText = string.match(message, "^/money%s+(%d+)%s*$")
	if amountText == nil then
		return nil
	end

	local amount = tonumber(amountText)
	if not ValueValidation.IsFiniteNumber(amount) or amount % 1 ~= 0 then
		return nil
	end

	return amount
end

return table.freeze(MoneyCheatCommandRules)
