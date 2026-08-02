--[[
	职责：保存房屋接触反馈的纯表现参数。
	输入：无。
	输出：缩放倍率、放大时间和恢复时间。
	不负责：不选择建筑、不检测触碰、不播放动画。
]]

return table.freeze({
	ScaleMultiplier = 1.3,
	ExpandDuration = 0.2,
	ReturnDuration = 0.25,
})
