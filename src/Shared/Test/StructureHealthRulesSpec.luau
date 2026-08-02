local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StructureDurabilityConfigs = require(
	ReplicatedStorage.Shared.Building.StructureDurabilityConfigs
)
local StructureHealthRules = require(
	ReplicatedStorage.Shared.Building.StructureHealthRules
)

local StructureHealthRulesSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "StructureHealthRulesSpec: " .. message)
end

function StructureHealthRulesSpec.Run(): boolean
	local ordinary = StructureHealthRules.ApplyDamage(100, 100, 35)
	expect(ordinary.Accepted, "普通伤害被拒绝")
	expect(ordinary.DamageApplied == 35 and ordinary.RemainingHealth == 65, "普通伤害错误")
	expect(not ordinary.Depleted, "非致命伤害被标记为耗尽")

	local lethal = StructureHealthRules.ApplyDamage(20, 100, 99)
	expect(lethal.Accepted and lethal.DamageApplied == 20, "致命伤害没有按剩余生命截断")
	expect(lethal.RemainingHealth == 0 and lethal.Depleted, "致命伤害没有归零")
	expect(
		StructureHealthRules.ApplyDamage(0, 100, 10).Reason == "HealthDepleted",
		"耗尽状态仍接受伤害"
	)

	local migrated = StructureHealthRules.MigrateByRatio(25, 100, 160)
	expect(migrated == 40, "升级没有继承血量比例")
	expect(StructureHealthRules.Full(240) == 240, "满血规则错误")
	expect(StructureHealthRules.Full(0) == nil, "无效最大生命值被接受")

	for _, regionId in { "R1", "R2" } do
		local previous = 0
		for level = 1, 3 do
			local maxHealth = StructureDurabilityConfigs.GetMaxHealth(regionId, level)
			expect(maxHealth ~= nil and maxHealth > previous, regionId .. " 耐久等级没有递增")
			previous = maxHealth
		end
	end
	return true
end

return StructureHealthRulesSpec
