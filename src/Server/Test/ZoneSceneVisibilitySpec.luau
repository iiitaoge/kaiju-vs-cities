local ZoneSceneVisibility = require(script.Parent.Parent.ZoneSceneVisibility)

local Spec = {}

local function approximatelyEqual(a: number, b: number): boolean
	return math.abs(a - b) <= 1e-6
end

function Spec.Run(): boolean
	local container = Instance.new("Model")
	container.Name = "ZoneSceneVisibilitySpec"

	local part = Instance.new("Part")
	part.Transparency = 0.35
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	part.Parent = container

	local decal = Instance.new("Decal")
	decal.Transparency = 0.2
	decal.Parent = part

	local texture = Instance.new("Texture")
	texture.Transparency = 0.45
	texture.Parent = part

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Enabled = true
	surfaceGui.Parent = part

	local succeeded, outcome = xpcall(function()
		assert(ZoneSceneVisibility.IsVisible(container), "新容器初始应可见")
		assert(ZoneSceneVisibility.SetVisible(container, false), "首次隐藏应改变状态")
		assert(not ZoneSceneVisibility.IsVisible(container), "容器隐藏状态错误")
		assert(part.Transparency == 1, "隐藏时 BasePart Transparency 应为 1")
		assert(not part.CanCollide, "隐藏时 BasePart CanCollide 应关闭")
		assert(not part.CanTouch, "隐藏时 BasePart CanTouch 应关闭")
		assert(not part.CanQuery, "隐藏时 BasePart CanQuery 应关闭")
		assert(decal.Transparency == 1, "隐藏时 Decal Transparency 应为 1")
		assert(texture.Transparency == 1, "隐藏时 Texture Transparency 应为 1")
		assert(not surfaceGui.Enabled, "隐藏时 SurfaceGui 应关闭")

		assert(ZoneSceneVisibility.SetVisible(container, true), "首次恢复应改变状态")
		assert(ZoneSceneVisibility.IsVisible(container), "容器恢复状态错误")
		assert(
			approximatelyEqual(part.Transparency, 0.35),
			"BasePart Transparency 未精确恢复"
		)
		assert(part.CanCollide, "BasePart CanCollide 未精确恢复")
		assert(not part.CanTouch, "BasePart CanTouch 未精确恢复")
		assert(part.CanQuery, "BasePart CanQuery 未精确恢复")
		assert(
			approximatelyEqual(decal.Transparency, 0.2),
			"Decal Transparency 未精确恢复"
		)
		assert(
			approximatelyEqual(texture.Transparency, 0.45),
			"Texture Transparency 未精确恢复"
		)
		assert(surfaceGui.Enabled, "SurfaceGui Enabled 未精确恢复")
		return true
	end, debug.traceback)

	container:Destroy()
	if not succeeded then
		error(outcome)
	end
	return outcome
end

return Spec
