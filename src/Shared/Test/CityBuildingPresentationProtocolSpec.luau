local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(
	ReplicatedStorage.Shared.Building.CityBuildingPresentationProtocol
)

local CityBuildingPresentationProtocolSpec = {}

local function expectValid(command)
	local valid, reason = Protocol.Validate(command)
	assert(valid, "CityBuildingPresentationProtocolSpec: " .. (reason or "命令无效"))
end

function CityBuildingPresentationProtocolSpec.Run(): boolean
	expectValid({
		Kind = "RegionUpgrade",
		OwnerUserId = 1,
		RegionId = "R1",
		PreviousLevel = 1,
		NewLevel = 2,
		PresentationId = "Standard",
		BuildSpeedMultiplier = 1.5,
		HouseIds = { "R1-H1" },
	})
	expectValid({
		Kind = "HouseDestroyed",
		OwnerUserId = 1,
		RegionId = "R1",
		HouseId = "R1-H1",
		Level = 1,
		PresentationId = "Standard",
		BuildSpeedMultiplier = 1,
	})
	expectValid({
		Kind = "HouseRebuilding",
		OwnerUserId = 1,
		RegionId = "R1",
		HouseId = "R1-H1",
		Level = 2,
		PresentationId = "Standard",
		BuildSpeedMultiplier = 1,
	})

	local invalidLevel, reason = Protocol.Validate({
		Kind = "HouseRebuilding",
		OwnerUserId = 1,
		RegionId = "R1",
		HouseId = "R1-H1",
		Level = 0,
		PresentationId = "Standard",
		BuildSpeedMultiplier = 1,
	})
	assert(
		not invalidLevel and reason == "InvalidLevel",
		"CityBuildingPresentationProtocolSpec: 非法等级未被拒绝"
	)
	local invalidMultiplier, multiplierReason = Protocol.Validate({
		Kind = "HouseDestroyed",
		OwnerUserId = 1,
		RegionId = "R1",
		HouseId = "R1-H1",
		Level = 1,
		PresentationId = "Standard",
		BuildSpeedMultiplier = 0,
	})
	assert(
		not invalidMultiplier and multiplierReason == "InvalidBuildSpeedMultiplier",
		"CityBuildingPresentationProtocolSpec: 非法建造速度倍率未被拒绝"
	)
	return true
end

return CityBuildingPresentationProtocolSpec
