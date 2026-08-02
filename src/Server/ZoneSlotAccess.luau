local ZoneSlotAccess = {}

export type Slot = {
	ZoneId: string,
	ZoneKind: string,
	SlotId: string,
	SlotKind: string,
	Point: BasePart,
}

export type Access = {
	-- slotKind 为 nil 时返回所有已解锁 Zone 的 Slot，否则只返回指定 Kind。
	ListUnlockedSlots: (Player, string?) -> { Slot },
}

return ZoneSlotAccess
