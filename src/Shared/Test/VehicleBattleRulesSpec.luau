local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleBattleRules = require(ReplicatedStorage.Shared.Vehicle.VehicleBattleRules)

assert(VehicleBattleRules.ResolveRound(100, 10, 100, 10).Outcome == "Continue")
local defenderWins = VehicleBattleRules.ResolveRound(10, 10, 10, 10)
assert(defenderWins.Outcome == "Defender")
local attackerWins = VehicleBattleRules.ResolveRound(10, 10, 20, 20)
assert(attackerWins.Outcome == "Attacker")

return true
