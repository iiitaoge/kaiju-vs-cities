local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local LocalBuildingTouchController = require(script.Parent.LocalBuildingTouchController)

local houseEntered = InstancePath.Get("ReplicatedStorage/Remotes/HouseEntered")
assert(houseEntered:IsA("RemoteEvent"), "HouseEntered 必须是 RemoteEvent")

local LocalBuildingInteractionController = {}

function LocalBuildingInteractionController.Bind(
	houseId: string,
	model: Model,
	playContactFeedback: (Model) -> ()
): LocalBuildingTouchController.Handle
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(type(playContactFeedback) == "function", "playContactFeedback 必须是 function")

	return LocalBuildingTouchController.Bind(model, {
		OnEntered = function()
			-- 本地接触反馈与服务端收入意图使用同一个 OnEntered；表现失败不得阻断收入请求。
			task.spawn(playContactFeedback, model)
			houseEntered:FireServer("Enter", houseId)
		end,
		OnExited = function()
			houseEntered:FireServer("Exit", houseId)
		end,
	})
end

return LocalBuildingInteractionController
