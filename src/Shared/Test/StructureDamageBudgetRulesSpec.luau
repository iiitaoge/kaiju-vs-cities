local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StructureDamageBudgetRules = require(
	ReplicatedStorage.Shared.Building.StructureDamageBudgetRules
)

local StructureDamageBudgetRulesSpec = {}

function StructureDamageBudgetRulesSpec.Run(): boolean
	local remainingDamage = 8_000
	local destroyedCount = 0
	for _ = 1, 6 do
		local allocation = StructureDamageBudgetRules.Allocate(remainingDamage, 1_500)
		remainingDamage = allocation.RemainingDamage
		if allocation.WillDestroy then
			destroyedCount += 1
		end
	end
	assert(destroyedCount == 5, "8000 伤害只能完整摧毁 5 栋 1500 HP 房屋")
	assert(remainingDamage == 0, "伤害预算必须完整消耗")

	local finalHit = StructureDamageBudgetRules.Allocate(500, 1_500)
	assert(finalHit.DamageToApply == 500, "最后一栋必须接受剩余的部分伤害")
	assert(not finalHit.WillDestroy, "部分伤害不得误判摧毁")
	assert(finalHit.RemainingDamage == 0, "部分命中后预算应归零")
	return true
end

return StructureDamageBudgetRulesSpec
