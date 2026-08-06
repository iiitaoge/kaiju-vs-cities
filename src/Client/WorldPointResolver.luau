--[[
	职责：把原始鼠标或触摸的 viewport 坐标解析为世界射线命中点。
	输入：DeviceSafe viewport 坐标；GetMouseLocation 可直接使用，InputObject.Position 必须先加左上 GUI inset。
	输出：首个世界射线命中位置；无相机或无命中时返回 nil。
	内部算法：ViewportPointToRay 创建射线，再向 Workspace 发射固定最大距离的 Raycast。
	不负责：调用方的 screen -> viewport 转换、命中合法性或 Raycast 过滤。
]]

local WorldPointResolver = {}

local MAX_RAY_DISTANCE = 10_000

function WorldPointResolver.Resolve(viewportPosition: Vector2): Vector3?
	assert(typeof(viewportPosition) == "Vector2", "viewportPosition must be a Vector2")

	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end

	local viewportRay = camera:ViewportPointToRay(viewportPosition.X, viewportPosition.Y)
	local result = workspace:Raycast(
		viewportRay.Origin,
		viewportRay.Direction * MAX_RAY_DISTANCE
	)

	if result == nil then
		return nil
	end

	return result.Position
end

return WorldPointResolver
