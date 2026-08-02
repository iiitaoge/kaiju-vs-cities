--[[
	职责：保存攻击目标浏览和出征跟随相机的第一版技术参数。
	不负责：创建 GUI、决定美术样式或保存玩家偏好。
]]

local browseCamera = table.freeze({
	FieldOfView = 55,
	PaddingRatio = 0.15,
	TransitionDuration = 0.35,
	RestoreDuration = 0.25,
})

local followCamera = table.freeze({
	Offset = Vector3.new(0, 18, 30),
	FieldOfView = 70,
	Responsiveness = 8,
})

return table.freeze({
	BrowseCamera = browseCamera,
	FollowCamera = followCamera,
})
