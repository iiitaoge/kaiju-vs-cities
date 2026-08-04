--[[
	职责：保存房屋自动重建链路的纯配置。
	输入：调用方读取 Default。
	输出：摧毁等待、失败重试、区域占用轮询和表现配置 ID。
	不负责：不读取房屋状态、不调度任务、不播放动画。
]]

local default = {
	RebuildDelaySeconds = 10,
	RetryDelaySeconds = 2,
	OccupancyPollIntervalSeconds = 0.25,
	PresentationId = "Standard",
}

table.freeze(default)

return table.freeze({
	Default = default,
})
