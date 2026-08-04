local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterMovementRules = require(
	ReplicatedStorage.Shared.Monster.MonsterMovementRules
)

local Spec = {}

local function near(actual: number, expected: number, message: string)
	assert(math.abs(actual - expected) <= 1e-6, message)
end

function Spec.Run(): boolean
	local movement = {
		MoveSpeed = 40,
		MaxTravelDuration = 3,
		TimingSafetyMargin = 0.1,
		TurnDuration = 0.2,
	}
	near(
		MonsterMovementRules.ResolveMoveSpeed(40, movement),
		40,
		"近距离不得被最长到达时间降速"
	)
	local longDistanceSpeed = MonsterMovementRules.ResolveMoveSpeed(1_200, movement)
	near(
		0.2 + 0.1 + 1_200 / longDistanceSpeed,
		3,
		"1200 studs 必须为实际调度预留余量并在 3 秒内到达"
	)

	local animation = {
		ReferenceMoveSpeed = 40,
		MinPlaybackSpeed = 1,
		MaxPlaybackSpeed = 3,
	}
	near(
		MonsterMovementRules.ResolveWalkAnimationSpeed(40, animation),
		1,
		"基础移速动画倍率错误"
	)
	near(
		MonsterMovementRules.ResolveWalkAnimationSpeed(80, animation),
		2,
		"动画没有随实际移速同步"
	)
	near(
		MonsterMovementRules.ResolveWalkAnimationSpeed(longDistanceSpeed, animation),
		3,
		"远距离动画倍率没有正确封顶"
	)
	near(
		MonsterMovementRules.ResolveDetectionRadius(30, 400, 0.15),
		90,
		"高速移动检测半径错误"
	)
	return true
end

return Spec
