--[[
	职责：播放单个临时建筑从地下由低到高升起的建造动画。
	输入：模板、最终 Pivot、地面 Y 和升起参数。
	输出：动画结束后销毁临时 Clone，无持久 Model 输出。
	不负责：不显示服务器权威建筑，不解析模板。
]]

local TweenService = game:GetService("TweenService")

local LocalBuildingRiseAnimation = {}

local function getParts(model: Model): { BasePart }
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			table.insert(parts, descendant)
		end
	end
	table.sort(parts, function(a, b)
		if math.abs(a.Position.Y - b.Position.Y) > 0.01 then
			return a.Position.Y < b.Position.Y
		end
		return a:GetFullName() < b:GetFullName()
	end)
	return parts
end

function LocalBuildingRiseAnimation.Play(
	template: Model,
	targetPivot: CFrame,
	groundY: number,
	config
)
	assert(template:IsA("Model"), "template 必须是 Model")
	assert(typeof(targetPivot) == "CFrame", "targetPivot 必须是 CFrame")
	assert(type(groundY) == "number", "groundY 必须是 number")

	local visual = template:Clone()
	visual.Name = template.Name .. "_Rising"
	visual:PivotTo(targetPivot)
	visual.Parent = workspace

	local parts = getParts(visual)
	local targets = {}
	local transparencies = {}
	local undergroundY = groundY - config.MoveDistance
	for _, part in parts do
		targets[part] = part.CFrame
		transparencies[part] = part.Transparency
		part.Transparency = 1
		part.CFrame += Vector3.new(0, undergroundY - part.Position.Y, 0)
	end

	local startWindow = math.max(0, config.TotalDuration - config.MoveDuration)
	for index, part in parts do
		local startDelay = if #parts > 1
			then (index - 1) / (#parts - 1) * startWindow
			else 0
		local tween = TweenService:Create(
			part,
			TweenInfo.new(config.MoveDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				CFrame = targets[part],
				Transparency = transparencies[part],
			}
		)
		task.delay(startDelay, function()
			if part.Parent then
				tween:Play()
			end
		end)
	end

	task.wait(config.TotalDuration)
	visual:Destroy()
end

return LocalBuildingRiseAnimation
