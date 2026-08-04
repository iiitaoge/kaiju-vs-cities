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
	UnlockPrerequisiteZoneId: string?,
	UnlockPrerequisiteLevel: number?,
	Slots: { [string]: SlotDefinition },
}

local definitions: { [string]: ZoneDefinition } = {
	D1 = {
		ZoneId = "D1",
		Kind = "Defense",
		InitialUnlocked = false,
		Slots = {
			["D1-T1"] = { SlotId = "D1-T1", Kind = "DefenseTower" },
		},
	},
	M1 = {
		ZoneId = "M1",
		Kind = "MonsterSpawn",
		InitialUnlocked = true,
		Slots = {
			["M1-S1"] = { SlotId = "M1-S1", Kind = "MonsterSpawnPoint" },
			["M1-S2"] = { SlotId = "M1-S2", Kind = "MonsterSpawnPoint" },
			["M1-S3"] = { SlotId = "M1-S3", Kind = "MonsterSpawnPoint" },
			["M1-S4"] = { SlotId = "M1-S4", Kind = "MonsterSpawnPoint" },
		},
	},
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
		InitialUnlocked = true,
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
	R3 = {
		ZoneId = "R3",
		Kind = "Income",
		InitialUnlocked = false,
		UnlockPrerequisiteZoneId = "R2",
		UnlockPrerequisiteLevel = 5,
		Slots = {
			["R3-H1"] = { SlotId = "R3-H1", Kind = "IncomeBuilding" },
			["R3-H2"] = { SlotId = "R3-H2", Kind = "IncomeBuilding" },
			["R3-H3"] = { SlotId = "R3-H3", Kind = "IncomeBuilding" },
			["R3-H4"] = { SlotId = "R3-H4", Kind = "IncomeBuilding" },
			["R3-H5"] = { SlotId = "R3-H5", Kind = "IncomeBuilding" },
			["R3-H6"] = { SlotId = "R3-H6", Kind = "IncomeBuilding" },
			["R3-H7"] = { SlotId = "R3-H7", Kind = "IncomeBuilding" },
			["R3-H8"] = { SlotId = "R3-H8", Kind = "IncomeBuilding" },
		},
	},
	R4 = {
		ZoneId = "R4",
		Kind = "Income",
		InitialUnlocked = false,
		UnlockPrerequisiteZoneId = "R3",
		UnlockPrerequisiteLevel = 5,
		Slots = {
			["R4-A1"] = { SlotId = "R4-A1", Kind = "IncomeBuilding" },
			["R4-A2"] = { SlotId = "R4-A2", Kind = "IncomeBuilding" },
			["R4-H1"] = { SlotId = "R4-H1", Kind = "IncomeBuilding" },
			["R4-H2"] = { SlotId = "R4-H2", Kind = "IncomeBuilding" },
			["R4-H3"] = { SlotId = "R4-H3", Kind = "IncomeBuilding" },
			["R4-H4"] = { SlotId = "R4-H4", Kind = "IncomeBuilding" },
			["R4-H5"] = { SlotId = "R4-H5", Kind = "IncomeBuilding" },
			["R4-H6"] = { SlotId = "R4-H6", Kind = "IncomeBuilding" },
			["R4-H7"] = { SlotId = "R4-H7", Kind = "IncomeBuilding" },
		},
	},
	R5 = {
		ZoneId = "R5",
		Kind = "Income",
		InitialUnlocked = false,
		UnlockPrerequisiteZoneId = "R4",
		UnlockPrerequisiteLevel = 5,
		Slots = {
			["R5-H1"] = { SlotId = "R5-H1", Kind = "IncomeBuilding" },
			["R5-H2"] = { SlotId = "R5-H2", Kind = "IncomeBuilding" },
			["R5-H3"] = { SlotId = "R5-H3", Kind = "IncomeBuilding" },
			["R5-H4"] = { SlotId = "R5-H4", Kind = "IncomeBuilding" },
			["R5-H5"] = { SlotId = "R5-H5", Kind = "IncomeBuilding" },
		},
	},
	R6 = {
		ZoneId = "R6",
		Kind = "Income",
		InitialUnlocked = false,
		UnlockPrerequisiteZoneId = "R5",
		UnlockPrerequisiteLevel = 5,
		Slots = {
			["R6-A1"] = { SlotId = "R6-A1", Kind = "IncomeBuilding" },
			["R6-A2"] = { SlotId = "R6-A2", Kind = "IncomeBuilding" },
			["R6-H1"] = { SlotId = "R6-H1", Kind = "IncomeBuilding" },
			["R6-H2"] = { SlotId = "R6-H2", Kind = "IncomeBuilding" },
			["R6-H3"] = { SlotId = "R6-H3", Kind = "IncomeBuilding" },
			["R6-H4"] = { SlotId = "R6-H4", Kind = "IncomeBuilding" },
			["R6-H5"] = { SlotId = "R6-H5", Kind = "IncomeBuilding" },
			["R6-H6"] = { SlotId = "R6-H6", Kind = "IncomeBuilding" },
			["R6-H7"] = { SlotId = "R6-H7", Kind = "IncomeBuilding" },
			["R6-H8"] = { SlotId = "R6-H8", Kind = "IncomeBuilding" },
			["R6-H9"] = { SlotId = "R6-H9", Kind = "IncomeBuilding" },
			["R6-H10"] = { SlotId = "R6-H10", Kind = "IncomeBuilding" },
			["R6-H11"] = { SlotId = "R6-H11", Kind = "IncomeBuilding" },
			["R6-H12"] = { SlotId = "R6-H12", Kind = "IncomeBuilding" },
			["R6-H13"] = { SlotId = "R6-H13", Kind = "IncomeBuilding" },
		},
	},
}

local sortedDefinitions: { ZoneDefinition } = {}
local slotOwnerById: { [string]: string } = {}

for zoneId, definition in pairs(definitions) do
	assert(definition.ZoneId == zoneId, string.format("ZoneId 与配置键不一致：%s", zoneId))
	assert(type(definition.Kind) == "string" and definition.Kind ~= "", "Zone Kind 必须是非空字符串")
	local prerequisiteZoneId = definition.UnlockPrerequisiteZoneId
	local prerequisiteLevel = definition.UnlockPrerequisiteLevel
	if prerequisiteZoneId then
		assert(prerequisiteZoneId ~= zoneId, "Zone 解锁前置不能指向自身：" .. zoneId)
		assert(
			definitions[prerequisiteZoneId] ~= nil,
			string.format("Zone %s 的解锁前置不存在：%s", zoneId, prerequisiteZoneId)
		)
		assert(
			type(prerequisiteLevel) == "number"
				and prerequisiteLevel >= 1
				and prerequisiteLevel % 1 == 0,
			zoneId .. " 的解锁前置等级无效"
		)
	else
		assert(prerequisiteLevel == nil, zoneId .. " 没有前置 Zone 却配置了前置等级")
	end

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
