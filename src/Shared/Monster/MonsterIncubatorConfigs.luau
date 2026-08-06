--[[
	职责：保存培养罐建造表现、释放和恢复的纯配置。
	输入：调用方按 SpawnPointId 读取，再以怪兽 FormIndex 查询罐体模板。
	输出：形态到模板的显式映射、定位/表现身份，以及三个开合阶段的时间和缓动。
	不负责：解析场景、Clone、移动对象、怪兽状态或购买事务。
]]

local release = {
	Liquid = { Duration = 1, StartNextAt = 0.6 },
	Glass = { Duration = 1, StartNextAt = 0.6 },
	Base = { Duration = 0.8 },
}
local restore = {
	Base = { Duration = 0.8, StartNextAt = 0.6 },
	Glass = { Duration = 1, StartNextAt = 0.6 },
	Liquid = { Duration = 1 },
}
local templateIdsByForm = table.freeze({
	[1] = "PetriDish-1",
	[2] = "PetriDish-2",
	[3] = "PetriDish-3",
	[4] = "PetriDish-4",
	[5] = "PetriDish-5",
})

for _, group in { release, restore } do
	for _, step in group do
		table.freeze(step)
	end
	table.freeze(group)
end

local function standard(spawnPointId: string)
	return table.freeze({
		ZoneId = "M1",
		IncubatorSlotId = spawnPointId,
		TemplateRootName = "MonsterIncubators",
		TemplateIdsByForm = templateIdsByForm,
		PresentationId = "MonsterStandard",
		EasingStyle = Enum.EasingStyle.Sine,
		EasingDirection = Enum.EasingDirection.InOut,
		Release = release,
		Restore = restore,
	})
end

return table.freeze({
	["M1-S1"] = standard("M1-S1"),
	["M1-S2"] = standard("M1-S2"),
	["M1-S3"] = standard("M1-S3"),
	["M1-S4"] = standard("M1-S4"),
})
