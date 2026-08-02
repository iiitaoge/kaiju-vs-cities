-- Studio 默认关闭真实 DataStore，避免本地测试误写线上数据；需要联调存档时只开启此开关。
return table.freeze({
	ProductionStoreName = "PlayerSave",
	StudioStoreName = "PlayerSave_Development",
	StudioEnabled = true,
	KeyPrefix = "Player_",
	AutosaveIntervalSeconds = 60,
	SessionLeaseSeconds = 180,
	ShutdownWaitSeconds = 25,
	LoadAttempts = 3,
	SaveAttempts = 3,
	RetryDelaySeconds = 1,
	FailedSaveRetryDelaySeconds = 10,
})
