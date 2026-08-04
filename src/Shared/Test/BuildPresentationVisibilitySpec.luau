local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildPresentationVisibility = require(
	ReplicatedStorage.Shared.Building.BuildPresentationVisibility
)

local BuildPresentationVisibilitySpec = {}

local function expectNear(actual: number, expected: number, message: string)
	assert(math.abs(actual - expected) < 1e-5, message)
end

function BuildPresentationVisibilitySpec.Run(): boolean
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.Transparency = 0.25
	part.Parent = model
	local decal = Instance.new("Decal")
	decal.Transparency = 0.4
	decal.Parent = part

	assert(BuildPresentationVisibility.Hide(model), "首次隐藏应改变模型状态")
	assert(BuildPresentationVisibility.IsHidden(model), "模型缺少建造隐藏标记")
	assert(part.Transparency == 1 and decal.Transparency == 1, "模型没有在 Parent 前完全隐藏")
	expectNear(
		BuildPresentationVisibility.ResolveTransparency(part),
		0.25,
		"零件最终透明度快照错误"
	)
	expectNear(
		BuildPresentationVisibility.ResolveTransparency(decal),
		0.4,
		"表面贴图最终透明度快照错误"
	)
	assert(not BuildPresentationVisibility.Hide(model), "重复隐藏不应覆盖原透明度")

	assert(BuildPresentationVisibility.Restore(model), "首次恢复应改变模型状态")
	assert(not BuildPresentationVisibility.IsHidden(model), "恢复后仍残留建造隐藏标记")
	expectNear(part.Transparency, 0.25, "没有恢复零件原透明度")
	expectNear(decal.Transparency, 0.4, "没有恢复表面贴图原透明度")
	assert(not BuildPresentationVisibility.Restore(model), "重复恢复应为幂等无变化")

	model:Destroy()
	return true
end

return BuildPresentationVisibilitySpec
