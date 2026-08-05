local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterDuelOutcomeRules = require(
	ReplicatedStorage.Shared.Monster.MonsterDuelOutcomeRules
)

assert(MonsterDuelOutcomeRules.Resolve(2, 1) == "Attacker")
assert(MonsterDuelOutcomeRules.Resolve(1, 2) == "Defender")
assert(MonsterDuelOutcomeRules.Resolve(5, 5) == "Defender")

return true
