--[[
	职责：计算培养罐 UI 的水平接近判定。
	输入：玩家位置、罐体位置和最大距离。
	输出：玩家与罐体的水平距离，以及是否进入显示范围。
	内部算法：只计算 X/Z 平面的直线距离。
	不负责：读取 Workspace、显示屏幕 UI 或监听每帧事件。
]]

local MonsterIncubatorUIPlacement = {}

local function horizontalOffset(fromPosition: Vector3, toPosition: Vector3): Vector3
	return Vector3.new(
		toPosition.X - fromPosition.X,
		0,
		toPosition.Z - fromPosition.Z
	)
end

function MonsterIncubatorUIPlacement.IsWithinHorizontalDistance(
	playerPosition: Vector3,
	incubatorPosition: Vector3,
	maxDistance: number
): boolean
	assert(typeof(playerPosition) == "Vector3", "playerPosition 必须是 Vector3")
	assert(typeof(incubatorPosition) == "Vector3", "incubatorPosition 必须是 Vector3")
	assert(
		type(maxDistance) == "number" and maxDistance >= 0 and maxDistance < math.huge,
		"maxDistance 无效"
	)
	return MonsterIncubatorUIPlacement.HorizontalDistance(
		playerPosition,
		incubatorPosition
	) <= maxDistance
end

function MonsterIncubatorUIPlacement.HorizontalDistance(
	playerPosition: Vector3,
	incubatorPosition: Vector3
): number
	assert(typeof(playerPosition) == "Vector3", "playerPosition 必须是 Vector3")
	assert(typeof(incubatorPosition) == "Vector3", "incubatorPosition 必须是 Vector3")
	return horizontalOffset(incubatorPosition, playerPosition).Magnitude
end

return table.freeze(MonsterIncubatorUIPlacement)
