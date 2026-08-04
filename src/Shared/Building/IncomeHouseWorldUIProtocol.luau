--[[
	职责：定义服务器写入运行时房屋、客户端只读监听的世界 UI Attribute 名称。
	输入/输出：无函数；纯跨端协议常量。
	不负责：计算收入、生命、生命周期或创建 UI。
]]

return table.freeze({
	LifeStateAttributeName = "BuildingUILifeState",
	AutoIncomeAttributeName = "BuildingUIAutoIncome",
	IncomePerSecondAttributeName = "BuildingUIIncomePerSecond",
	StoredMoneyAttributeName = "BuildingUIStoredMoney",
	LastIncomeAtAttributeName = "BuildingUILastIncomeAt",
	CurrentHealthAttributeName = "BuildingCurrentHealth",
	MaxHealthAttributeName = "BuildingMaxHealth",
})
