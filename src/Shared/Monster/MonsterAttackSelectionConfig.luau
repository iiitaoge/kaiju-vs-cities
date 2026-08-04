--[[
	职责：保存攻击目标浏览、世界准星和出征跟随相机的技术参数。
	不负责：创建 GUI/模型、决定攻击合法性或保存玩家偏好。
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

local crosshair = table.freeze({
	TemplateName = "Crosshair",
	AnimationAssetId = 100062745080464,
	SurfaceOffset = 0.05,
})

return table.freeze({
	BrowseCamera = browseCamera,
	FollowCamera = followCamera,
	Crosshair = crosshair,
})
