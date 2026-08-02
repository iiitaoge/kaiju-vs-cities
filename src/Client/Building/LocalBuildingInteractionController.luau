local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local LocalBuildingEffectPlayer = require(script.Parent.LocalBuildingEffectPlayer)
local LocalBuildingTouchController = require(script.Parent.LocalBuildingTouchController)

local houseEntered = InstancePath.Get("ReplicatedStorage/Remotes/HouseEntered")
assert(houseEntered:IsA("RemoteEvent"), "HouseEntered 必须是 RemoteEvent")

local LocalBuildingInteractionController = {}

function LocalBuildingInteractionController.Bind(
	houseId: string,
	model: Model
): LocalBuildingTouchController.Handle
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	assert(model:IsA("Model"), "model 必须是 Model")

	return LocalBuildingTouchController.Bind(model, {
		OnEntered = function()
			task.spawn(LocalBuildingEffectPlayer.PlayContact, model)
			houseEntered:FireServer("Enter", houseId)
		end,
		OnExited = function()
			houseEntered:FireServer("Exit", houseId)
		end,
	})
end

return LocalBuildingInteractionController
