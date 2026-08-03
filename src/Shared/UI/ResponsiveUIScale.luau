--[[
	职责：把视口尺寸与输入设备转换为稳定的 UI 缩放倍率。
	输入：当前 ViewportSize、是否支持触屏，以及参考视口/缩放边界配置。
	输出：限制在配置范围内的缩放倍率。
	内部算法：取宽高相对参考视口的较小比例，限制上下限；触屏再应用可点击尺寸下限。
	不负责：读取 Camera、创建 UIScale、监听分辨率变化或决定具体 UI 尺寸。
]]

local ResponsiveUIScale = {}

export type Config = {
	ReferenceViewport: Vector2,
	MinScale: number,
	MaxScale: number,
	TouchMinScale: number,
}

function ResponsiveUIScale.Compute(
	viewportSize: Vector2,
	isTouchEnabled: boolean,
	config: Config
): number
	assert(typeof(viewportSize) == "Vector2", "viewportSize 必须是 Vector2")
	assert(viewportSize.X > 0 and viewportSize.Y > 0, "viewportSize 必须大于 0")
	assert(type(isTouchEnabled) == "boolean", "isTouchEnabled 必须是 boolean")
	assert(type(config) == "table", "config 必须是 table")
	assert(
		typeof(config.ReferenceViewport) == "Vector2"
			and config.ReferenceViewport.X > 0
			and config.ReferenceViewport.Y > 0,
		"ReferenceViewport 无效"
	)
	assert(type(config.MinScale) == "number" and config.MinScale > 0, "MinScale 无效")
	assert(
		type(config.MaxScale) == "number" and config.MaxScale >= config.MinScale,
		"MaxScale 无效"
	)
	assert(
		type(config.TouchMinScale) == "number"
			and config.TouchMinScale >= config.MinScale
			and config.TouchMinScale <= config.MaxScale,
		"TouchMinScale 无效"
	)

	local widthRatio = viewportSize.X / config.ReferenceViewport.X
	local heightRatio = viewportSize.Y / config.ReferenceViewport.Y
	local scale = math.clamp(math.min(widthRatio, heightRatio), config.MinScale, config.MaxScale)
	if isTouchEnabled then
		scale = math.max(scale, config.TouchMinScale)
	end
	return scale
end

return table.freeze(ResponsiveUIScale)
