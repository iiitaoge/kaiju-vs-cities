--[[
	职责：计算怪兽单次移动的权威速度、行走动画倍率和高速检测半径。
	输入：水平距离、移动配置、动画配置或检测参数。
	输出：有限正数速度/倍率/半径。
	内部算法：基础速度不降速；远距离速度覆盖“转向 + 移动”的最长总时长；
		动画按实际速度相对参考速度缩放并限幅；检测半径加入速度前视距离。
	不负责：移动模型、播放动画、选择目标或读取 Workspace。
]]

local MonsterMovementRules = {}

local function finite(value): boolean
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

function MonsterMovementRules.ResolveMoveSpeed(distance: number, config): number
	assert(finite(distance) and distance >= 0, "distance 必须是有限非负数")
	assert(type(config) == "table", "config 必须是 table")
	assert(finite(config.MoveSpeed) and config.MoveSpeed > 0, "MoveSpeed 必须大于 0")
	if config.MaxTravelDuration == nil then
		return config.MoveSpeed
	end

	assert(
		finite(config.MaxTravelDuration) and config.MaxTravelDuration > 0,
		"MaxTravelDuration 必须大于 0"
	)
	local turnDuration = config.TurnDuration or 0
	assert(finite(turnDuration) and turnDuration >= 0, "TurnDuration 必须是有限非负数")
	local safetyMargin = config.TimingSafetyMargin or 0
	assert(finite(safetyMargin) and safetyMargin >= 0, "TimingSafetyMargin 必须是有限非负数")
	local maxMoveDuration = config.MaxTravelDuration - turnDuration - safetyMargin
	assert(
		maxMoveDuration > 0,
		"MaxTravelDuration 必须大于 TurnDuration 与 TimingSafetyMargin 之和"
	)
	return math.max(config.MoveSpeed, distance / maxMoveDuration)
end

function MonsterMovementRules.ResolveWalkAnimationSpeed(
	moveSpeed: number,
	config
): number
	assert(finite(moveSpeed) and moveSpeed > 0, "moveSpeed 必须大于 0")
	if config == nil then
		return 1
	end
	assert(type(config) == "table", "行走动画 config 必须是 table")
	assert(
		finite(config.ReferenceMoveSpeed) and config.ReferenceMoveSpeed > 0,
		"ReferenceMoveSpeed 必须大于 0"
	)
	assert(
		finite(config.MinPlaybackSpeed) and config.MinPlaybackSpeed > 0,
		"MinPlaybackSpeed 必须大于 0"
	)
	assert(
		finite(config.MaxPlaybackSpeed)
			and config.MaxPlaybackSpeed >= config.MinPlaybackSpeed,
		"MaxPlaybackSpeed 必须不小于 MinPlaybackSpeed"
	)
	return math.clamp(
		moveSpeed / config.ReferenceMoveSpeed,
		config.MinPlaybackSpeed,
		config.MaxPlaybackSpeed
	)
end

function MonsterMovementRules.ResolveDetectionRadius(
	baseRadius: number,
	moveSpeed: number,
	lookAheadSeconds: number?
): number
	assert(finite(baseRadius) and baseRadius >= 0, "baseRadius 必须是有限非负数")
	assert(finite(moveSpeed) and moveSpeed >= 0, "moveSpeed 必须是有限非负数")
	local lookAhead = lookAheadSeconds or 0
	assert(finite(lookAhead) and lookAhead >= 0, "lookAheadSeconds 必须是有限非负数")
	return baseRadius + moveSpeed * lookAhead
end

return table.freeze(MonsterMovementRules)
