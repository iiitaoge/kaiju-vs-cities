local HouseHealthStateService = require(script.Parent.Parent.HouseHealthStateService)

local HouseHealthStateServiceSpec = {}

local HOUSE_ID = "Spec-HouseHealth"

local function expect(condition: boolean, message: string)
	assert(condition, "HouseHealthStateServiceSpec: " .. message)
end

-- 输入：一个 Player，仅作为会话状态隔离键。
-- 输出：比例升级、代次拒绝、无自动回血和重建满血均成立时返回 true。
-- 内部算法：满血初始化 → 扣血 → 同级 Ensure → 跨级迁移 → 旧代拒绝 → 重建重置。
function HouseHealthStateServiceSpec.Run(player: Player): boolean
	HouseHealthStateService.Clear(player)
	local initial = HouseHealthStateService.Ensure(player, HOUSE_ID, 1, 100)
	expect(initial.CurrentHealth == 100 and initial.Generation == 1, "首次访问必须满血")

	local damaged = HouseHealthStateService.ApplyDamage(player, HOUSE_ID, 1, 35)
	expect(
		damaged.Accepted and damaged.CurrentHealth == 65 and damaged.DamageApplied == 35,
		"普通伤害结算错误"
	)
	local sameLevel = HouseHealthStateService.Ensure(player, HOUSE_ID, 1, 100)
	expect(sameLevel.CurrentHealth == 65, "同一会话内 Ensure 不得自动回血")

	local upgraded = HouseHealthStateService.Ensure(player, HOUSE_ID, 2, 160)
	expect(
		upgraded.CurrentHealth == 104 and upgraded.Generation == 2,
		"升级必须按 65% 比例迁移并换代"
	)
	local stale = HouseHealthStateService.ApplyDamage(player, HOUSE_ID, 1, 10)
	expect(not stale.Accepted and stale.Reason == "StaleHealthGeneration", "旧代伤害必须拒绝")

	local rebuilt = HouseHealthStateService.ResetFull(player, HOUSE_ID, 3, 240)
	expect(
		rebuilt.CurrentHealth == 240 and rebuilt.Generation == 3,
		"重建必须采用最新等级满血并换代"
	)
	expect(HouseHealthStateService.Clear(player) == 1, "清理数量错误")
	expect(HouseHealthStateService.Get(player, HOUSE_ID) == nil, "清理后仍有会话血量")
	return true
end

return HouseHealthStateServiceSpec
