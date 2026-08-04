--[[
	职责：按建造速度倍率缩放建筑表现时间。
	输入：有限正数时长或包含 MoveDistance/TotalDuration/MoveDuration 的动作配置，以及有限正倍率。
	输出：缩放后的时长，或不修改输入的只读动作配置。
	内部算法：所有耗时除以速度倍率；空间位移保持不变。
	不负责：读取玩家、重生状态、表现配置、播放动画或等待。
]]

local BuildPresentationTiming = {}

local function assertPositiveFinite(value: number, name: string)
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value > 0,
		name .. " 必须是有限正数"
	)
end

function BuildPresentationTiming.ScaleDuration(
	duration: number,
	buildSpeedMultiplier: number
): number
	assertPositiveFinite(duration, "duration")
	assertPositiveFinite(buildSpeedMultiplier, "buildSpeedMultiplier")
	return duration / buildSpeedMultiplier
end

function BuildPresentationTiming.ScaleMotion(config, buildSpeedMultiplier: number)
	assert(type(config) == "table", "config 必须是 table")
	assertPositiveFinite(config.MoveDistance, "config.MoveDistance")
	assertPositiveFinite(config.TotalDuration, "config.TotalDuration")
	assertPositiveFinite(config.MoveDuration, "config.MoveDuration")
	assert(config.MoveDuration <= config.TotalDuration, "MoveDuration 不得超过 TotalDuration")

	return table.freeze({
		MoveDistance = config.MoveDistance,
		TotalDuration = BuildPresentationTiming.ScaleDuration(
			config.TotalDuration,
			buildSpeedMultiplier
		),
		MoveDuration = BuildPresentationTiming.ScaleDuration(
			config.MoveDuration,
			buildSpeedMultiplier
		),
	})
end

return table.freeze(BuildPresentationTiming)
