--[[
	职责：保存房屋收入飘字和触碰金币飞行动画的纯表现参数。
	输入：无。
	输出：世界飘字尺寸、时间和偏移，以及金币数量、尺寸、错峰与飞行时间。
	不负责：读取 HUD、查找房屋、创建 UI、监听 Remote 或播放动画。
]]

return table.freeze({
	PopupSize = Vector2.new(60, 16),
	PopupIconSize = 30,
	PopupBaseOffsetStuds = 1.5,
	PopupRiseStuds = 2.5,
	PopupDuration = 0.8,
	PopupFadeDelay = 0.2,
	PopupMaxDistance = 250,
	TouchCoinCount = 5,
	TouchCoinSize = 32,
	TouchCoinScatterPixels = 24,
	TouchCoinStaggerSeconds = 0.06,
	TouchCoinFlightSeconds = 0.7,
})
