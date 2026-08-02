--[[
	职责：
	- 保存建筑变化的纯表现参数。

	输入：
	- 由调用方使用 PresentationId 读取配置。

	输出：
	- 拆除、升起的位移与时间参数，以及等待运行时建筑复制的超时时间。

	不负责：
	- 不选择建筑、不读取玩家状态、不播放动画。
]]

local standard = {
	ResolveTimeout = 5,
	Demolish = {
		MoveDistance = 8,
		TotalDuration = 0.5,
		MoveDuration = 0.15,
	},
	Rise = {
		MoveDistance = 8,
		TotalDuration = 1,
		MoveDuration = 0.25,
	},
}

table.freeze(standard.Demolish)
table.freeze(standard.Rise)
table.freeze(standard)

return table.freeze({
	Standard = standard,
})
