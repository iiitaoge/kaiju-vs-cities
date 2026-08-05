--[[
	职责：声明 GameAnalytics 接入的稳定配置合同。
	输入：无。
	输出：ServerStorage Attribute 名称、Build 缺省值和 Resource 白名单。
	内部算法：无；只提供冻结配置。
	不负责：读取凭据、初始化 SDK、发送事件或计算玩法数值。
]]

return table.freeze({
	GameKeyAttribute = "GameAnalyticsGameKey",
	SecretKeyAttribute = "GameAnalyticsSecretKey",
	BuildAttribute = "GameAnalyticsBuild",
	DebugAttribute = "GameAnalyticsDebug",
	ClientEnabledAttribute = "GameAnalyticsEnabled",
	DefaultBuild = "0.1.0",
	Currency = "Money",
	ResourceItemTypes = table.freeze({
		"Income",
		"Region",
		"Boost",
		"Monster",
		"Combat",
	}),
	AutoIncomeFlushIntervalSeconds = 60,
	SecurityFlushIntervalSeconds = 60,
	IntentRateWindowSeconds = 10,
	IntentRateLimit = 30,
	SessionLoadFunnelName = "SessionLoad",
	AttackLaunchFunnelName = "AttackLaunch",
	MonsterUpgradeFunnelName = "MonsterUpgrade",
	RebirthFunnelName = "Rebirth",
})
