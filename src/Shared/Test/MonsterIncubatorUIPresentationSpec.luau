local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterIncubatorUIPresentationConfig = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorUIPresentationConfig
)
local MonsterIncubatorUIPlacement = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorUIPlacement
)
local ResponsiveUIScale = require(ReplicatedStorage.Shared.UI.ResponsiveUIScale)

local MonsterIncubatorUIPresentationSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "MonsterIncubatorUIPresentationSpec: " .. message)
end

local function expectNear(actual: number, expected: number, message: string)
	expect(math.abs(actual - expected) <= 1e-5, message)
end

-- 输入：桌面/手机视口、屏幕位置配置和接近距离边界。
-- 输出：缩放、显示范围及安全区内屏幕定位合同稳定时返回 true。
-- 内部算法：验证缩放上下限、触屏下限、右侧居中锚点和接近距离边界。
function MonsterIncubatorUIPresentationSpec.Run(): boolean
	local config = MonsterIncubatorUIPresentationConfig
	local scaleConfig = config.ResponsiveScale
	expect(config.ScreenAnchorPoint == Vector2.new(1, 0.5), "屏幕 UI 必须右侧居中锚定")
	expect(config.ScreenPosition.X.Scale == 1, "屏幕 UI 必须贴近安全区右侧")
	expect(config.ScreenPosition.X.Offset < 0, "屏幕 UI 必须保留右侧边距")
	expect(config.ScreenPosition.Y.Scale == 0.5, "屏幕 UI 必须垂直居中")
	expectNear(
		ResponsiveUIScale.Compute(Vector2.new(960, 720), false, scaleConfig),
		1,
		"参考视口应使用 1 倍缩放"
	)
	expectNear(
		ResponsiveUIScale.Compute(Vector2.new(480, 360), false, scaleConfig),
		0.85,
		"小型非触屏视口应受最小缩放限制"
	)
	expectNear(
		ResponsiveUIScale.Compute(Vector2.new(480, 360), true, scaleConfig),
		1,
		"触屏视口不应小于可点击尺寸下限"
	)
	expectNear(
		ResponsiveUIScale.Compute(Vector2.new(1920, 1080), false, scaleConfig),
		1.15,
		"大型视口应受最大缩放限制"
	)

	local center = Vector3.new(10, 20, 30)
	expectNear(
		MonsterIncubatorUIPlacement.HorizontalDistance(
			center + Vector3.new(3, 100, 4),
			center
		),
		5,
		"最近培养罐选择距离必须忽略高度"
	)
	expect(
		MonsterIncubatorUIPlacement.IsWithinHorizontalDistance(
			center + Vector3.new(20, 100, 0),
			center,
			config.HorizontalActivationDistance
		),
		"边界距离应显示且忽略垂直差"
	)
	expect(
		not MonsterIncubatorUIPlacement.IsWithinHorizontalDistance(
			center + Vector3.new(20.01, 0, 0),
			center,
			config.HorizontalActivationDistance
		),
		"超出水平边界仍然显示"
	)
	expect(table.isfrozen(ResponsiveUIScale), "响应式缩放模块必须只读")
	expect(table.isfrozen(MonsterIncubatorUIPlacement), "定位模块必须只读")
	expect(table.isfrozen(config), "培养罐 UI 配置必须只读")
	expect(table.isfrozen(scaleConfig), "响应式缩放子配置必须只读")
	return true
end

return MonsterIncubatorUIPresentationSpec
