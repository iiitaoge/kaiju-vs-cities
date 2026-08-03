--[[
	职责：播放单个临时建筑从高到低沉入地下的拆除动画。
	输入：模板、最终 Pivot、地面 Y 和拆除参数。
	输出：动画结束后销毁临时 Clone，无持久 Model 输出。
	不负责：不隐藏或销毁服务器权威建筑，不解析模板。
]]

local TweenService = game:GetService("TweenService")

local LocalBuildingAnimationPartPreparer = require(
	script.Parent.LocalBuildingAnimationPartPreparer
)

local LocalBuildingDemolitionAnimation = {}

function LocalBuildingDemolitionAnimation.Play(
	template: Model,
	targetPivot: CFrame,
	groundY: number,
	config
)
	assert(template:IsA("Model"), "template 必须是 Model")
	assert(typeof(targetPivot) == "CFrame", "targetPivot 必须是 CFrame")
	assert(type(groundY) == "number", "groundY 必须是 number")

	local visual = template:Clone()
	visual.Name = template.Name .. "_Demolishing"
	visual:PivotTo(targetPivot)
	visual.Parent = workspace

	local items = LocalBuildingAnimationPartPreparer.Prepare(
		visual,
		"HighToLow"
	)
	local undergroundY = groundY - config.MoveDistance
	local startWindow = math.max(0, config.TotalDuration - config.MoveDuration)
	for index, item in items do
		local part = item.Part
		local startDelay = if #items > 1
			then (index - 1) / (#items - 1) * startWindow
			else 0
		local tweenInfo = TweenInfo.new(
			config.MoveDuration,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.In
		)
		local tween = TweenService:Create(
			part,
			tweenInfo,
			{
				CFrame = part.CFrame + Vector3.new(0, undergroundY - part.Position.Y, 0),
				Transparency = 1,
			}
		)
		local surfaceTweens = {}
		for _, surfaceVisual in item.SurfaceVisuals do
			table.insert(surfaceTweens, TweenService:Create(
				surfaceVisual,
				tweenInfo,
				{ Transparency = 1 }
			))
		end
		task.delay(startDelay, function()
			if part.Parent then
				tween:Play()
			end
			for surfaceIndex, surfaceTween in surfaceTweens do
				if item.SurfaceVisuals[surfaceIndex].Parent then
					surfaceTween:Play()
				end
			end
		end)
	end

	task.wait(config.TotalDuration)
	visual:Destroy()
end

return LocalBuildingDemolitionAnimation
