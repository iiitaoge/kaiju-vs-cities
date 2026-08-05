return {
	-- 正式玩家 Plot 怪兽链已启用；旧的单场景测试链默认关闭，避免依赖 Workspace/MonsterAttackTest。
	Enabled = false,
	HouseIdPrefix = "TEST-",
	MonsterKey = "Godzilla-L001",

	Paths = {
		HouseTemplate = "ReplicatedStorage/TestFixtures/MonsterAttackTest/HouseTemplates/TestHouse",
		HousePoints = "Workspace/MonsterAttackTest/HousePoints",
		MonsterTemplate = "ReplicatedStorage/Godzilla/P1/Start",
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
