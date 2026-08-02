local LocalTouchTriggerFactory = {}

local TRIGGER_NAME = "_LocalTouchTrigger"

function LocalTouchTriggerFactory.Create(model: Model): BasePart
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(not model:FindFirstChild(TRIGGER_NAME), "Model 已经存在本地触碰触发器")

	local triggerCFrame, triggerSize = model:GetBoundingBox()
	local trigger = Instance.new("Part")
	trigger.Name = TRIGGER_NAME
	trigger.Size = triggerSize
	trigger.CFrame = triggerCFrame
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanQuery = false
	trigger.CanTouch = true
	trigger.CastShadow = false
	trigger.Transparency = 1
	trigger.Parent = model

	return trigger
end

return LocalTouchTriggerFactory
