-- Studio 只连接独立开发 Store；正式服务器始终使用 ProductionStoreName。
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
