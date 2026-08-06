local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatHealthBarPresentationRules = require(
	ReplicatedStorage.Shared.UI.CombatHealthBarPresentationRules
)

local CombatHealthBarPresentationRulesSpec = {}

function CombatHealthBarPresentationRulesSpec.Run(): boolean
	local idle = CombatHealthBarPresentationRules.ResolveMonster({
		State = "IdleAtSpawn",
		CurrentHealth = 80,
		MaxHealth = 100,
	})
	assert(not idle.Enabled, "罐内怪兽不得显示战斗血条")

	for _, state in {
		"Releasing",
		"MovingToTarget",
		"AttackingStructure",
		"FightingMonster",
		"Returning",
		"Defending",
	} do
		local presentation = CombatHealthBarPresentationRules.ResolveMonster({
			State = state,
			CurrentHealth = 75,
			MaxHealth = 100,
		})
		assert(presentation.Enabled, state .. " 怪兽血条未启用")
		assert(presentation.FillRatio == 0.75, state .. " 怪兽血量比例错误")
		assert(presentation.Text == "75/100", state .. " 怪兽血量文本错误")
	end

	local inactiveHouse = CombatHealthBarPresentationRules.ResolveHouse({
		LifeState = "Alive",
		ActiveAttackCount = 0,
		CurrentHealth = 1_250,
		MaxHealth = 2_500,
	})
	assert(not inactiveHouse.Enabled, "未被攻击房屋不得显示战斗血条")

	local attackedHouse = CombatHealthBarPresentationRules.ResolveHouse({
		LifeState = "Alive",
		ActiveAttackCount = 2,
		CurrentHealth = 1_250,
		MaxHealth = 2_500,
	})
	assert(attackedHouse.Enabled, "被集火房屋血条未启用")
	assert(attackedHouse.FillRatio == 0.5, "房屋血量比例错误")
	assert(attackedHouse.Text == "1.25K/2.5K", "房屋动态血量文本错误")

	return true
end

return CombatHealthBarPresentationRulesSpec
