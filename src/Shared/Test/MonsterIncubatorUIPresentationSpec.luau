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

-- 输入：桌面/手机视口、罐体四个观察方向和接近距离边界。
-- 输出：缩放、显示范围及外表面定位合同稳定时返回 true。
-- 内部算法：验证缩放上下限与触屏下限，并用四个方位检查位置始终落在摄像头近侧。
function MonsterIncubatorUIPresentationSpec.Run(): boolean
	local config = MonsterIncubatorUIPresentationConfig
	local scaleConfig = config.ResponsiveScale
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

	local glassSize = Vector3.new(22, 20, 22)
	local expectedRadius = glassSize.X * 0.5 + config.SurfacePadding
	for _, direction in {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
	} do
		local position = MonsterIncubatorUIPlacement.ResolveWorldPosition(
			center,
			glassSize,
			center + direction * 50,
			center + direction * 10,
			config.SurfacePadding,
			config.VerticalOffsetRatio
		)
		local horizontal = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
		expectNear(horizontal.Magnitude, expectedRadius, "UI 未落在罐体外表面")
		expect(horizontal:Dot(direction) > 0, "UI 未落在摄像头近侧")
		expectNear(
			position.Y,
			center.Y + glassSize.Y * config.VerticalOffsetRatio,
			"UI 高度未落在罐体中下部"
		)
	end

	expect(table.isfrozen(ResponsiveUIScale), "响应式缩放模块必须只读")
	expect(table.isfrozen(MonsterIncubatorUIPlacement), "定位模块必须只读")
	expect(table.isfrozen(config), "培养罐 UI 配置必须只读")
	expect(table.isfrozen(scaleConfig), "响应式缩放子配置必须只读")
	return true
end

return MonsterIncubatorUIPresentationSpec
