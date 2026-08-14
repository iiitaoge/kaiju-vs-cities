--[[
	职责：定义任务系统跨模块共用的类型标识。
	输入：无。
	输出：要求类型、事件类型、进度类型和奖励类型常量。
	内部算法：无；只提供冻结常量。
	不负责：任务配置校验、进度计算、状态保存或奖励发放。
]]

local TaskProtocol = {}

TaskProtocol.RequirementKinds = table.freeze({
	UnlockZone = "UnlockZone",
	ReachRegionLevel = "ReachRegionLevel",
	BuildHouse = "BuildHouse",
	UpgradeMonster = "UpgradeMonster",
	EarnMoney = "EarnMoney",
})

TaskProtocol.EventKinds = table.freeze({
	ZoneUnlocked = "ZoneUnlocked",
	RegionLevelChanged = "RegionLevelChanged",
	HouseBuilt = "HouseBuilt",
	MonsterUpgraded = "MonsterUpgraded",
	MoneyEarned = "MoneyEarned",
})

TaskProtocol.ProgressKinds = table.freeze({
	Boolean = "Boolean",
	Counter = "Counter",
	Level = "Level",
})

TaskProtocol.RewardKinds = table.freeze({
	Money = "Money",
	Diamond = "Diamond",
})

return table.freeze(TaskProtocol)
