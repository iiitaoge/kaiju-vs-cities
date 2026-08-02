--[[
	职责：
	- 定义所有玩家地块共用的稳定 ZoneId、Zone Kind 和 Slot 身份。
	- Zone 是空间与解锁单位；具体业务由 Kind 和 SlotKind 对应的系统解释。

	输入：
	- Get：zoneId。
	- GetSlot：zoneId、slotId。
	- GetAll：无。

	输出：
	- 不可变的 Zone/Slot 定义，或按 ZoneId 排序的新数组。

	不负责：
	- 不读取 Workspace，不保存玩家状态，不执行区域业务。
	- 不保存 Plot 的世界坐标；所有 Plot 通过相同 ZoneId/SlotId 关联场景。
]]

local ZoneCatalog = {}

export type SlotDefinition = {
	SlotId: string,
	Kind: string,
}

export type ZoneDefinition = {
	ZoneId: string,
	Kind: string,
	InitialUnlocked: boolean,
	Slots: { [string]: SlotDefinition },
}

local definitions: { [string]: ZoneDefinition } = {
	R1 = {
		ZoneId = "R1",
		Kind = "Income",
		InitialUnlocked = true,
		Slots = {
			["R1-H1"] = { SlotId = "R1-H1", Kind = "IncomeBuilding" },
			["R1-H2"] = { SlotId = "R1-H2", Kind = "IncomeBuilding" },
			["R1-H3"] = { SlotId = "R1-H3", Kind = "IncomeBuilding" },
			["R1-H4"] = { SlotId = "R1-H4", Kind = "IncomeBuilding" },
			["R1-H5"] = { SlotId = "R1-H5", Kind = "IncomeBuilding" },
			["R1-H6"] = { SlotId = "R1-H6", Kind = "IncomeBuilding" },
			["R1-H7"] = { SlotId = "R1-H7", Kind = "IncomeBuilding" },
			["R1-H8"] = { SlotId = "R1-H8", Kind = "IncomeBuilding" },
		},
	},
	R2 = {
		ZoneId = "R2",
		Kind = "Income",
		InitialUnlocked = false,
		Slots = {
			["R2-H1"] = { SlotId = "R2-H1", Kind = "IncomeBuilding" },
			["R2-H2"] = { SlotId = "R2-H2", Kind = "IncomeBuilding" },
			["R2-H3"] = { SlotId = "R2-H3", Kind = "IncomeBuilding" },
			["R2-H4"] = { SlotId = "R2-H4", Kind = "IncomeBuilding" },
			["R2-H5"] = { SlotId = "R2-H5", Kind = "IncomeBuilding" },
			["R2-H6"] = { SlotId = "R2-H6", Kind = "IncomeBuilding" },
			["R2-H7"] = { SlotId = "R2-H7", Kind = "IncomeBuilding" },
			["R2-H8"] = { SlotId = "R2-H8", Kind = "IncomeBuilding" },
		},
	},
}

local sortedDefinitions: { ZoneDefinition } = {}
local slotOwnerById: { [string]: string } = {}

for zoneId, definition in pairs(definitions) do
	assert(definition.ZoneId == zoneId, string.format("ZoneId 与配置键不一致：%s", zoneId))
	assert(type(definition.Kind) == "string" and definition.Kind ~= "", "Zone Kind 必须是非空字符串")

	for slotId, slot in pairs(definition.Slots) do
		assert(slot.SlotId == slotId, string.format("SlotId 与配置键不一致：%s", slotId))
		assert(not slotOwnerById[slotId], string.format("重复的全局 SlotId：%s", slotId))
		assert(type(slot.Kind) == "string" and slot.Kind ~= "", "Slot Kind 必须是非空字符串")
		slotOwnerById[slotId] = zoneId
		table.freeze(slot)
	end

	table.freeze(definition.Slots)
	table.freeze(definition)
	table.insert(sortedDefinitions, definition)
end

table.sort(sortedDefinitions, function(a, b)
	return a.ZoneId < b.ZoneId
end)
table.freeze(sortedDefinitions)
table.freeze(definitions)

function ZoneCatalog.Get(zoneId: string): ZoneDefinition?
	return definitions[zoneId]
end

function ZoneCatalog.GetSlot(zoneId: string, slotId: string): SlotDefinition?
	local definition = definitions[zoneId]
	return if definition then definition.Slots[slotId] else nil
end

-- 输出数组本身可修改，内部不可变定义不会被复制。
function ZoneCatalog.GetAll(): { ZoneDefinition }
	return table.clone(sortedDefinitions)
end

return ZoneCatalog
