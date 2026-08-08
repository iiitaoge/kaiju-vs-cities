local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NestRewardRules = require(ReplicatedStorage.Shared.Nest.NestRewardRules)

assert(NestRewardRules.CalculatePayout(10, 1, 3) == 30)
assert(NestRewardRules.CalculatePayout(10, 1.25, 3) == 37)

return true
