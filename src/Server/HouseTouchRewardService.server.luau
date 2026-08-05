local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SecurityAnalyticsAggregator = require(
	script.Parent.Analytics.SecurityAnalyticsAggregator
)
local HouseInteractionService = require(script.Parent.HouseInteractionService)
local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local DebugLog = require(ReplicatedStorage.Shared.DebugLog)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)

local houseEntered = InstancePath.Get("ReplicatedStorage/Remotes/HouseEntered")
assert(houseEntered:IsA("RemoteEvent"), "HouseEntered 必须是 RemoteEvent")

local log = DebugLog.Create("HouseInteractionService")

houseEntered.OnServerEvent:Connect(function(player, action, houseId)
	if PlayerDataReadyService.Get(player).Status ~= "Ready" then
		return
	end
	if action ~= "Enter" and action ~= "Exit" then
		SecurityAnalyticsAggregator.Record(player, "HouseEntered", "InvalidAction")
	end
	if type(houseId) ~= "string" or houseId == "" then
		SecurityAnalyticsAggregator.Record(player, "HouseEntered", "InvalidHouseId")
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
end)
