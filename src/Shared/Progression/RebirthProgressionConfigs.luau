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

local function rewardText(
	income: string,
	build: string,
	damage: string,
	health: string,
	move: string
): string
	return table.concat({
		"Next rewards:",
		"Income x" .. income,
		"Build x" .. build,
		"Damage x" .. damage,
		"HP x" .. health,
		"Move x" .. move,
	}, "\n")
end

local config = {
	Button = {
		ButtonName = "Rebirth-Button",
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

	-- 下一次重生的展示文案。键是重生完成后的次数；Default 覆盖未来新增次数。
	Presentation = {
		[1] = {
			LevelText = "Kaiju max Lv. 15 → 30",
			RewardText = rewardText("1.25", "1.1", "1.15", "1.1", "1.02"),
		},
		[2] = {
			LevelText = "Kaiju max Lv. 30 → 45",
			RewardText = rewardText("1.5", "1.2", "1.3", "1.2", "1.04"),
		},
		[3] = {
			LevelText = "Kaiju max Lv. 45 → 60",
			RewardText = rewardText("1.75", "1.3", "1.45", "1.3", "1.06"),
		},
		[4] = {
			LevelText = "Kaiju max Lv. 60 → 75",
			RewardText = rewardText("2", "1.4", "1.6", "1.4", "1.08"),
		},
		[5] = {
			LevelText = "Kaiju max Lv. 75 · All forms unlocked",
			RewardText = rewardText("2.25", "1.5", "1.75", "1.5", "1.1"),
		},
		Default = {
			LevelText = "Kaiju max Lv. 75 · All forms unlocked",
			RewardText = "Next rewards:\nPermanent bonuses continue to grow",
		},
	},
}

for _, bonus in pairs(config.Bonuses) do
	table.freeze(bonus)
end
table.freeze(config.Button)
table.freeze(config.Eligibility)
table.freeze(config.Bonuses)
for _, presentation in pairs(config.Presentation) do
	assert(
		type(presentation.LevelText) == "string" and presentation.LevelText ~= "",
		"重生展示缺少 LevelText"
	)
	assert(
		type(presentation.RewardText) == "string" and presentation.RewardText ~= "",
		"重生展示缺少 RewardText"
	)
	table.freeze(presentation)
end
table.freeze(config.Presentation)

return table.freeze(config)
