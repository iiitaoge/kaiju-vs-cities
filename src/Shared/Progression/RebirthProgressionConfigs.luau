--[[
	职责：集中定义重生资格和五项永久倍率的首版平衡参数。
	输入：无。
	输出：资格门槛配置，以及按重生次数线性增长的倍率配置。
	内部算法：无；所有数值只作为 RebirthProgressionRules 的输入。
	不负责：读取玩家状态、判断资格、应用倍率、写存档或重置进度。

	倍率语义：
	- IncomeMultiplier：收入乘以该值。
	- BuildSpeedMultiplier：建造耗时除以该值。
	- MonsterDamageMultiplier / MonsterHealthMultiplier：对应基础数值乘以该值。
	- MonsterMoveSpeedMultiplier：怪兽基础移动速度乘以该值。
]]

local config = {
	Button = {
		ModelPath = "Workspace/Buttons/Rebirth-Button",
		MaxActivationDistance = 12,
		RefreshIntervalSeconds = 0.5,
		-- BillboardGui 的底边与整个按钮模型顶面之间保留的世界高度。
		UIBottomClearanceStuds = 1,
	},

	Eligibility = {
		BaseRequiredRunEarnings = 1_000_000,
		RequirementGrowth = 5,
		MaximumRequiredRunEarnings = 1e30,
	},

	Bonuses = {
		IncomeMultiplier = {
			BaseMultiplier = 1,
			PerRebirth = 0.25,
			MaximumMultiplier = 10,
		},
		BuildSpeedMultiplier = {
			BaseMultiplier = 1,
			PerRebirth = 0.10,
			MaximumMultiplier = 3,
		},
		MonsterDamageMultiplier = {
			BaseMultiplier = 1,
			PerRebirth = 0.15,
			MaximumMultiplier = 10,
		},
		MonsterHealthMultiplier = {
			BaseMultiplier = 1,
			PerRebirth = 0.10,
			MaximumMultiplier = 5,
		},
		MonsterMoveSpeedMultiplier = {
			BaseMultiplier = 1,
			PerRebirth = 0.02,
			MaximumMultiplier = 1.5,
		},
	},
}

for _, bonus in pairs(config.Bonuses) do
	table.freeze(bonus)
end
table.freeze(config.Button)
table.freeze(config.Eligibility)
table.freeze(config.Bonuses)

return table.freeze(config)
