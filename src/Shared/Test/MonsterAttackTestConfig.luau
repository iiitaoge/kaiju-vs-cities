return {
	Enabled = true,
	HouseIdPrefix = "TEST-",
	MonsterKey = "P4",

	Paths = {
		HouseTemplate = "ReplicatedStorage/TestFixtures/MonsterAttackTest/HouseTemplates/TestHouse",
		HousePoints = "Workspace/MonsterAttackTest/HousePoints",
		MonsterTemplate = "ReplicatedStorage/Godzilla/P4",
		MonsterSpawnPoint = "Workspace/MonsterAttackTest/MonsterSpawnPoint",
		CameraTarget = "Workspace/MonsterAttackTest/CameraTarget",
		Runtime = "Workspace/MonsterAttackTest/Runtime",
	},

	Camera = {
		Height = 120,
		FieldOfView = 85,
		EnterDuration = 1,
		RestoreDuration = 1,
	},

	Movement = {
		MoveSpeed = 16,
		TurnDuration = 0.75,
	},

	RewardAmount = 10,
}
