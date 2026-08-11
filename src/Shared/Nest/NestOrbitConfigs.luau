--[[
	职责：配置载具从玩家 Plot 前往 Nest，以及到达后的圆周运动参数。
	输入：GetRadius 接收 NestId；其余字段由运行时运动服务读取。
	输出：Nest0 独立半径、其他 Nest 默认半径、行驶速度、绕圈周期、出生高度偏移和车头角度偏移。
	内部算法：Nest0 读取独立半径，其余 Nest 读取 DefaultRadius；不读取场景、不移动模型。
	不负责：载具拥有关系、Nest 占用、战斗或奖励。
]]

local values = {
	-- 先给可运行的默认值，后续直接手调这里的数值即可。
	Nest0Radius = 145,
	DefaultRadius = 60,
	TravelSpeed = 80,
	OrbitPeriodSeconds = 12,
	ArrivalDistance = 0.5,
	-- 相对载具派遣出生时 Pivot 高度的手调偏移；0 表示保持出生高度。
	HeightOffset = 0,
	-- FrontMarker 判据的额外角度修正；正常放置 Marker 时保持 0。
	FrontYawOffset = 0,
}

local function getRadius(nestId: string): number
	return if nestId == "Nest0" then values.Nest0Radius else values.DefaultRadius
end

values.GetRadius = getRadius

return table.freeze(values)
