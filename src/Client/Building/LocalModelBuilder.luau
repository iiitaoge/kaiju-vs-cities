local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingPlacement = require(ReplicatedStorage.Shared.Building.BuildingPlacement)
local LocalModelPropertyApplier = require(script.Parent.LocalModelPropertyApplier)

local LocalModelBuilder = {}

local MOVE_DISTANCE = 8	-- 每个零件初始位置距离目标位置多远
local TOTAL_DURATION = 1	-- 整个模型完成建造的时间
local MOVE_DURATION = 0.25	-- 单个零件升起的时间

local function getPartsFromLowToHigh(model: Model): { BasePart }
	local parts = {}

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
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

function LocalModelBuilder.Build(template: Model, targetCFrame: CFrame): Model
	assert(template:IsA("Model"), "LocalModelBuilder.Build expected a Model")
	assert(typeof(targetCFrame) == "CFrame", "LocalModelBuilder.Build expected a CFrame")

	local targetPivot = BuildingPlacement.GetTargetPivot(template, targetCFrame)

	local visual = template:Clone()
	visual.Name = template.Name .. "_Building"
	visual:PivotTo(targetPivot)

	local parts = getPartsFromLowToHigh(visual)
	local targetCFrames = {}
	local targetTransparencies = {}
	local undergroundY = targetCFrame.Position.Y - MOVE_DISTANCE
	LocalModelPropertyApplier.Apply(visual, {
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	})

	for _, part in parts do
		targetCFrames[part] = part.CFrame
		targetTransparencies[part] = part.Transparency
		part.Transparency = 1
		part.CFrame += Vector3.new(0, undergroundY - part.Position.Y, 0)
	end
	visual.Parent = workspace

	local startWindow = TOTAL_DURATION - MOVE_DURATION

	for index, part in parts do
		local startDelay = if #parts > 1
			then (index - 1) / (#parts - 1) * startWindow
			else 0
		local tween = TweenService:Create(
			part,
			TweenInfo.new(MOVE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				CFrame = targetCFrames[part],
				Transparency = targetTransparencies[part],
			}
		)

		task.delay(startDelay, function()
			tween:Play()
		end)
	end

	task.wait(TOTAL_DURATION)

	local finalModel = template:Clone()
	LocalModelPropertyApplier.Apply(finalModel, {
		CanCollide = false,
	})

	finalModel:PivotTo(targetPivot)
	finalModel.Parent = workspace
	visual:Destroy()

	return finalModel
end

return LocalModelBuilder
