local TweenService = game:GetService("TweenService")

local LocalModelPropertyApplier = require(script.Parent.LocalModelPropertyApplier)

local LocalModelDemolisher = {}

local MOVE_DISTANCE = 8
local TOTAL_DURATION = 0.5
local MOVE_DURATION = 0.15

local function getPartsFromHighToLow(model: Model): { BasePart }
	local parts = {}

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	table.sort(parts, function(a, b)
		if math.abs(a.Position.Y - b.Position.Y) > 0.01 then
			return a.Position.Y > b.Position.Y
		end

		return a:GetFullName() < b:GetFullName()
	end)

	return parts
end

function LocalModelDemolisher.Demolish(model: Model)
	assert(model:IsA("Model"), "LocalModelDemolisher.Demolish expected a Model")
	assert(model.Parent, "Cannot demolish a Model without a parent")

	local visual = model:Clone()
	visual.Name = model.Name .. "_Demolishing"
	visual.Parent = model.Parent
	model:Destroy()

	local undergroundY = visual:GetPivot().Position.Y - MOVE_DISTANCE
	local parts = getPartsFromHighToLow(visual)
	LocalModelPropertyApplier.Apply(visual, {
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	})

	local startWindow = TOTAL_DURATION - MOVE_DURATION

	for index, part in parts do
		local startDelay = if #parts > 1
			then (index - 1) / (#parts - 1) * startWindow
			else 0
		local tween = TweenService:Create(
			part,
			TweenInfo.new(MOVE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{
				CFrame = part.CFrame + Vector3.new(0, undergroundY - part.Position.Y, 0),
				Transparency = 1,
			}
		)

		task.delay(startDelay, function()
			tween:Play()
		end)
	end

	task.wait(TOTAL_DURATION)
	visual:Destroy()
end

return LocalModelDemolisher
