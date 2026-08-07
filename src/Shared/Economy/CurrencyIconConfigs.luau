--[[
	职责：定义货币图标在 ReplicatedStorage 数据树中的位置和名称。
	输入：无；客户端根据货币类型读取这份只读配置。
	输出：图标根路径和货币类型到图标节点名称的映射。
	内部算法：无；纯配置。
	不负责：奖励金额、余额、图标实例创建或 UI 布局。
]]

local CurrencyProtocol = require(script.Parent.CurrencyProtocol)

local types = CurrencyProtocol.Types

return table.freeze({
	-- 对应 ReplicatedStorage/Assets/CurrencyIcons。
	RootPath = table.freeze({ "Assets", "CurrencyIcons" }),
	IconNames = table.freeze({
		[types.Money] = "Money",
		[types.Diamond] = "Diamond",
	}),
})
