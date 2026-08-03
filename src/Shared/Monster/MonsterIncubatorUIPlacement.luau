--[[
	职责：计算培养罐 UI 的水平接近判定和摄像头近侧世界位置。
	输入：玩家、罐体、摄像头位置，以及罐体尺寸和位置参数。
	输出：是否进入显示范围，或 UI 在罐体外表面的世界坐标。
	内部算法：接近判定只使用 X/Z 距离；位置取摄像头水平方向并落在圆柱外半径与中下部高度。
	不负责：读取 Workspace、移动 Attachment、设置 BillboardGui 或监听每帧事件。
]]

local MonsterIncubatorUIPlacement = {}

local DIRECTION_EPSILON = 1e-6

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
	return horizontalOffset(incubatorPosition, playerPosition).Magnitude <= maxDistance
end

function MonsterIncubatorUIPlacement.ResolveWorldPosition(
	glassPosition: Vector3,
	glassSize: Vector3,
	cameraPosition: Vector3,
	fallbackViewerPosition: Vector3,
	surfacePadding: number,
	verticalOffsetRatio: number
): Vector3
	assert(typeof(glassPosition) == "Vector3", "glassPosition 必须是 Vector3")
	assert(typeof(glassSize) == "Vector3", "glassSize 必须是 Vector3")
	assert(typeof(cameraPosition) == "Vector3", "cameraPosition 必须是 Vector3")
	assert(typeof(fallbackViewerPosition) == "Vector3", "fallbackViewerPosition 必须是 Vector3")
	assert(
		type(surfacePadding) == "number" and surfacePadding >= 0 and surfacePadding < math.huge,
		"surfacePadding 无效"
	)
	assert(
		type(verticalOffsetRatio) == "number"
			and verticalOffsetRatio > -0.5
			and verticalOffsetRatio < 0.5,
		"verticalOffsetRatio 无效"
	)

	local direction = horizontalOffset(glassPosition, cameraPosition)
	if direction.Magnitude <= DIRECTION_EPSILON then
		direction = horizontalOffset(glassPosition, fallbackViewerPosition)
	end
	if direction.Magnitude <= DIRECTION_EPSILON then
		direction = Vector3.new(0, 0, -1)
	else
		direction = direction.Unit
	end

	local horizontalRadius = math.max(glassSize.X, glassSize.Z) * 0.5
	return glassPosition
		+ direction * (horizontalRadius + surfacePadding)
		+ Vector3.new(0, glassSize.Y * verticalOffsetRatio, 0)
end

return table.freeze(MonsterIncubatorUIPlacement)
