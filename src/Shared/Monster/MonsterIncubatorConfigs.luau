--[[
	职责：保存培养罐建造表现、释放和恢复的纯配置。
	输入：调用方按 SpawnPointId 读取。
	输出：模板/定位/表现身份，以及三个开合阶段的时间和缓动。
	不负责：解析场景、Clone、移动对象、怪兽状态或购买事务。
]]

local standard = {
	ZoneId = "M1",
	IncubatorSlotId = "M1-S1",
	TemplateRootName = "MonsterIncubators",
	TemplateId = "PetriDish",
	PresentationId = "Standard",
	EasingStyle = Enum.EasingStyle.Sine,
	EasingDirection = Enum.EasingDirection.InOut,
	Release = {
		Liquid = { Duration = 1, StartNextAt = 0.6 },
		Glass = { Duration = 1, StartNextAt = 0.6 },
		Base = { Duration = 0.8 },
	},
	Restore = {
		Base = { Duration = 0.8, StartNextAt = 0.6 },
		Glass = { Duration = 1, StartNextAt = 0.6 },
		Liquid = { Duration = 1 },
	},
}

for _, groupName in { "Release", "Restore" } do
	for _, step in standard[groupName] do
		table.freeze(step)
	end
	table.freeze(standard[groupName])
end
table.freeze(standard)

return table.freeze({
	["M1-S1"] = standard,
})
