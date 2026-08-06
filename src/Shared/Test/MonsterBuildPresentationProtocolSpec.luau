local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Protocol = require(
	ReplicatedStorage.Shared.Monster.MonsterBuildPresentationProtocol
)

local MonsterBuildPresentationProtocolSpec = {}

local function expectValid(command)
	local valid, reason = Protocol.Validate(command)
	assert(valid, "MonsterBuildPresentationProtocolSpec: " .. (reason or "命令无效"))
end

function MonsterBuildPresentationProtocolSpec.Run(): boolean
	expectValid({
		Kind = "IncubatorBuild",
		OwnerUserId = -1,
		SpawnPointId = "M1-S1",
		PresentationId = "MonsterStandard",
		BuildSpeedMultiplier = 1,
		TemplateId = "PetriDish-1",
	})
	expectValid({
		Kind = "MonsterBuild",
		OwnerUserId = 1,
		SpawnPointId = "M1-S1",
		PresentationId = "MonsterStandard",
		BuildSpeedMultiplier = 1.2,
		MonsterKey = "Godzilla-L001",
	})
	expectValid({
		Kind = "MonsterUpgrade",
		OwnerUserId = 1,
		SpawnPointId = "M1-S1",
		PresentationId = "MonsterStandard",
		BuildSpeedMultiplier = 2,
		PreviousMonsterKey = "Godzilla-L015",
		MonsterKey = "Godzilla-L016",
		PreviousIncubatorTemplateId = "PetriDish-1",
		IncubatorTemplateId = "PetriDish-2",
		PreviousMonsterCFrame = CFrame.new(1, 2, 3),
	})

	for _, multiplier in { 0, -1, math.huge, 0 / 0 } do
		local valid, reason = Protocol.Validate({
			Kind = "IncubatorBuild",
			OwnerUserId = 1,
			SpawnPointId = "M1-S1",
			PresentationId = "MonsterStandard",
			BuildSpeedMultiplier = multiplier,
			TemplateId = "PetriDish-1",
		})
		assert(
			not valid and reason == "InvalidBuildSpeedMultiplier",
			"非法建造速度倍率未被拒绝"
		)
	end
	return true
end

return MonsterBuildPresentationProtocolSpec
