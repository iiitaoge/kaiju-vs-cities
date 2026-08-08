--[[
	职责：保存巢穴 Map 的镜头和刷新参数。
	输入：无。
	输出：Map 客户端使用的只读配置。
	内部算法：复用既有 CameraMarker 运镜的过渡、FOV 和恢复参数；不读取场景或玩家状态。
]]

return table.freeze({
	FirstNestId = "Nest0",
	MarkerName = "CameraMarker",
	TransitionDuration = 1.5,
	RestoreDuration = 0.75,
	FieldOfView = 70,
	Responsiveness = 8,
	RefreshIntervalSeconds = 1,
})
