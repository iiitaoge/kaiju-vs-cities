--[[
	职责：保存可重复购买的固定 Roblox Developer Product 配置。
	输入：调用方读取稳定 ProductId。
	输出：怪兽“升至满级”商品 ID；0 表示商品尚未在 Creator Hub 创建。
	内部算法：纯配置，不弹购买框、不处理收据、不发放权益。
	不负责：载具箱子商品；箱子商品跟随各自 Crate 配置保存。
]]

local PaidProductConfigs = {
	-- ProductId 确定后只修改这里，不修改收据处理逻辑。
	MonsterUpgradeToMaxProductId = 3705318281,
	MonsterUpgradeToMaxPriceInRobux = 299,
	MonsterUpgradeTargetLevel = "Max",
}

assert(
	type(PaidProductConfigs.MonsterUpgradeToMaxProductId) == "number"
		and PaidProductConfigs.MonsterUpgradeToMaxProductId >= 0
		and PaidProductConfigs.MonsterUpgradeToMaxProductId % 1 == 0,
	"MonsterUpgradeToMaxProductId 必须是非负整数"
)
assert(
	type(PaidProductConfigs.MonsterUpgradeToMaxPriceInRobux) == "number"
		and PaidProductConfigs.MonsterUpgradeToMaxPriceInRobux > 0
		and PaidProductConfigs.MonsterUpgradeToMaxPriceInRobux % 1 == 0,
	"MonsterUpgradeToMaxPriceInRobux 必须是正整数"
)
assert(
	PaidProductConfigs.MonsterUpgradeTargetLevel == "Max"
		or (
			type(PaidProductConfigs.MonsterUpgradeTargetLevel) == "number"
				and PaidProductConfigs.MonsterUpgradeTargetLevel >= 1
				and PaidProductConfigs.MonsterUpgradeTargetLevel % 1 == 0
		),
	"MonsterUpgradeTargetLevel 必须是 Max 或正整数"
)

return table.freeze(PaidProductConfigs)
