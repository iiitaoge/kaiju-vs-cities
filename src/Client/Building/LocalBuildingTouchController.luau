local Players = game:GetService("Players")

local LocalTouchTriggerFactory = require(script.Parent.LocalTouchTriggerFactory)

local LocalBuildingTouchController = {}

export type Callbacks = {
	OnEntered: ((Model) -> ())?,
	OnExited: ((Model) -> ())?,
}

export type Handle = {
	Destroy: (self: Handle) -> (),
}

local function belongsToLocalCharacter(part: BasePart): boolean
	local character = Players.LocalPlayer.Character
	return character ~= nil and part:IsDescendantOf(character)
end

function LocalBuildingTouchController.Bind(model: Model, callbacks: Callbacks?): Handle
	assert(model:IsA("Model"), "model 必须是 Model")

	local trigger = LocalTouchTriggerFactory.Create(model)
	local touchingParts = {}
	local connections = {}
	local isDestroyed = false

	local function emitExited()
		if next(touchingParts) == nil then
			return
		end

		table.clear(touchingParts)
		if callbacks and callbacks.OnExited then
			callbacks.OnExited(model)
		end
	end

	local handle = {} :: any

	function handle:Destroy()
		if isDestroyed then
			return
		end

		isDestroyed = true
		emitExited()

		for _, connection in connections do
			connection:Disconnect()
		end

		if trigger.Parent then
			trigger:Destroy()
		end
	end

	table.insert(connections, trigger.Touched:Connect(function(part)
		if not belongsToLocalCharacter(part) then
			return
		end

		local wasInside = next(touchingParts) ~= nil
		touchingParts[part] = true

		if not wasInside and callbacks and callbacks.OnEntered then
			callbacks.OnEntered(model)
		end
	end))

	table.insert(connections, trigger.TouchEnded:Connect(function(part)
		if not touchingParts[part] then
			return
		end

		touchingParts[part] = nil
		if next(touchingParts) == nil and callbacks and callbacks.OnExited then
			callbacks.OnExited(model)
		end
	end))

	table.insert(connections, Players.LocalPlayer.CharacterRemoving:Connect(emitExited))

	table.insert(connections, model.Destroying:Connect(function()
		handle:Destroy()
	end))

	return handle
end

return LocalBuildingTouchController
