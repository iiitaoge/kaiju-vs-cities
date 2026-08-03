--[[
	职责：保存培养罐近距离 UI 的位置、画布和响应式缩放参数。
	输入/输出：无函数；客户端按字段读取只读配置。
	内部算法：无；只集中保存表现参数，不读取玩家、Camera 或 Instance。
	不负责：距离检测、位置计算、UIScale 创建或管理状态。
]]

local responsiveScale = table.freeze({
	ReferenceViewport = Vector2.new(960, 720),
	MinScale = 0.85,
	MaxScale = 1.15,
	TouchMinScale = 1,
})

return table.freeze({
	HorizontalActivationDistance = 20,
	CameraMaxDistance = 80,
	BaseCanvasSize = Vector2.new(220, 220),
	SurfacePadding = 1.5,
	VerticalOffsetRatio = -0.4,
	ResponsiveScale = responsiveScale,
})
