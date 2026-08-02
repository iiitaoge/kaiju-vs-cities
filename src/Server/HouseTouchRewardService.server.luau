local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseInteractionService = require(script.Parent.HouseInteractionService)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local DebugLog = require(ReplicatedStorage.Shared.DebugLog)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)

local houseEntered = InstancePath.Get("ReplicatedStorage/Remotes/HouseEntered")
assert(houseEntered:IsA("RemoteEvent"), "HouseEntered 必须是 RemoteEvent")

local log = DebugLog.Create("HouseInteractionService")

houseEntered.OnServerEvent:Connect(function(player, action, houseId)
	if PlayerDataReadyService.Get(player).Status ~= "Ready" then
		houseEntered:FireClient(player, {
			Action = action,
			HouseId = houseId,
			Accepted = false,
			Reward = 0,
			Balance = nil,
			Reason = "PlayerDataNotReady",
		})
		return
	end
	local result = HouseInteractionService.Handle(player, action, houseId)
	log(
		player.Name,
		result.Action,
		result.HouseId,
		result.Accepted,
		result.Reason or "Accepted",
		result.Reward,
		result.Balance
	)
	houseEntered:FireClient(player, result)
end)
