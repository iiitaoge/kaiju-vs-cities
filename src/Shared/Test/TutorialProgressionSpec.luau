local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialProgression = require(
	ReplicatedStorage.Shared.Tutorial.TutorialProgression
)

local TutorialProgressionSpec = {}

local function expectStep(input, expected: string)
	local actual = TutorialProgression.Resolve(input)
	assert(
		actual == expected,
		string.format("TutorialProgressionSpec: expected %s, got %s", expected, actual)
	)
	assert(
		TutorialProgression.GetDefinition(actual) ~= nil,
		"TutorialProgressionSpec: every resolved step must have presentation copy"
	)
end

function TutorialProgressionSpec.Run(): boolean
	local r1UpgradeCost = 137
	local firstMonsterBuildCost = 421
	expectStep({
		CompletedVersion = 0,
		R1Level = 0,
		Money = 999,
		R1UpgradeCost = r1UpgradeCost,
		FirstMonsterBuildCost = firstMonsterBuildCost,
		FirstMonsterBuilt = false,
		FirstMonsterBuildInProgress = false,
	}, "BuildR1")
	expectStep({
		CompletedVersion = 0,
		R1Level = 1,
		Money = r1UpgradeCost - 1,
		R1UpgradeCost = r1UpgradeCost,
		FirstMonsterBuildCost = firstMonsterBuildCost,
		FirstMonsterBuilt = false,
		FirstMonsterBuildInProgress = false,
	}, "CollectForR1Upgrade")
	expectStep({
		CompletedVersion = 0,
		R1Level = 1,
		Money = r1UpgradeCost,
		R1UpgradeCost = r1UpgradeCost,
		FirstMonsterBuildCost = firstMonsterBuildCost,
		FirstMonsterBuilt = false,
		FirstMonsterBuildInProgress = false,
	}, "UpgradeR1")
	expectStep({
		CompletedVersion = 0,
		R1Level = 2,
		Money = firstMonsterBuildCost - 1,
		R1UpgradeCost = r1UpgradeCost,
		FirstMonsterBuildCost = firstMonsterBuildCost,
		FirstMonsterBuilt = false,
		FirstMonsterBuildInProgress = false,
	}, "CollectForMonsterBuild")
	expectStep({
		CompletedVersion = 0,
		R1Level = 2,
		Money = firstMonsterBuildCost,
		R1UpgradeCost = r1UpgradeCost,
		FirstMonsterBuildCost = firstMonsterBuildCost,
		FirstMonsterBuilt = false,
		FirstMonsterBuildInProgress = false,
	}, "BuildMonster")
	expectStep({
		CompletedVersion = 0,
		R1Level = 2,
		Money = 0,
		R1UpgradeCost = r1UpgradeCost,
		FirstMonsterBuildCost = firstMonsterBuildCost,
		FirstMonsterBuilt = false,
		FirstMonsterBuildInProgress = true,
	}, "WaitForMonsterBuild")
	expectStep({
		CompletedVersion = 0,
		R1Level = 2,
		Money = 0,
		R1UpgradeCost = r1UpgradeCost,
		FirstMonsterBuildCost = firstMonsterBuildCost,
		FirstMonsterBuilt = true,
		FirstMonsterBuildInProgress = false,
	}, "StartAttack")
	expectStep({
		CompletedVersion = TutorialProgression.CurrentVersion,
		R1Level = 0,
		Money = 0,
		R1UpgradeCost = r1UpgradeCost,
		FirstMonsterBuildCost = firstMonsterBuildCost,
		FirstMonsterBuilt = false,
		FirstMonsterBuildInProgress = false,
	}, "Complete")
	assert(
		TutorialProgression.GetDefinition("CollectForR1Upgrade").AmountKey
			== "R1UpgradeCost",
		"TutorialProgressionSpec: R1 collection copy must use the authoritative cost"
	)
	assert(
		TutorialProgression.GetDefinition("CollectForMonsterBuild").AmountKey
			== "FirstMonsterBuildCost",
		"TutorialProgressionSpec: monster collection copy must use the authoritative cost"
	)
	assert(
		TutorialProgression.GetDefinition("CollectForMonsterBuild").TargetKind
			== "R1MonsterBuildBuilding",
		"TutorialProgressionSpec: monster collection must target its dedicated R1 building"
	)
	assert(
		TutorialProgression.GetDefinition("WaitForMonsterBuild").TargetKind == nil,
		"TutorialProgressionSpec: monster build wait step must not have a guide target"
	)
	return true
end

return TutorialProgressionSpec
