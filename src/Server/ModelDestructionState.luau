local ModelDestructionState = {}

export type TransitionResult = {
	Changed: boolean,
	Previous: boolean,
	Current: boolean,
}

local ATTRIBUTE_NAME = "IsDestroyed"
local DEFAULT_STATE = false

local function validateModel(model: Model)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
end

local function readState(model: Model): boolean
	local value = model:GetAttribute(ATTRIBUTE_NAME)
	if value == nil then
		return DEFAULT_STATE
	end

	assert(type(value) == "boolean", "IsDestroyed Attribute 必须是 boolean")
	return value
end

function ModelDestructionState.Get(model: Model): boolean
	validateModel(model)
	return readState(model)
end

function ModelDestructionState.Set(model: Model, isDestroyed: boolean): TransitionResult
	validateModel(model)
	assert(type(isDestroyed) == "boolean", "isDestroyed 必须是 boolean")

	local previous = readState(model)
	if previous == isDestroyed then
		return {
			Changed = false,
			Previous = previous,
			Current = previous,
		}
	end

	model:SetAttribute(ATTRIBUTE_NAME, isDestroyed)

	return {
		Changed = true,
		Previous = previous,
		Current = isDestroyed,
	}
end

return ModelDestructionState
