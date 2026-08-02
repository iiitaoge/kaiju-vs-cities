local PlayerTerritoryAccess = {}

export type Territory = {
	ZoneId: string,
	BoundsId: string,
	CFrame: CFrame,
	Size: Vector3,
}

export type Access = {
	-- 输入在线玩家；输出其所有已解锁 Zone 的服务器权威范围快照。
	ListUnlockedTerritories: (Player) -> { Territory },
}

return PlayerTerritoryAccess
