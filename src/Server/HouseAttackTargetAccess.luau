local HouseAttackTargetAccess = {}

export type HouseTarget = {
	HouseId: string,
	CFrame: CFrame,
	Size: Vector3,
}

export type Access = {
	-- 输入 player；输出该玩家当前可参与攻击选择的房屋快照。
	ListAliveTargets: (player: Player) -> { HouseTarget },
	-- 输入 player、houseId；输出最新可攻击范围，失败时返回原因。
	ResolveAliveTarget: (player: Player, houseId: string) -> (HouseTarget?, string?),
	-- 输入 player、houseId；输出摧毁前业务准备是否成功及失败原因。
	PrepareDestroy: (player: Player, houseId: string) -> (boolean, string?),
	-- 输入 player、houseId；输出是否首次完成 Alive -> Destroyed 并同步运行时建筑。
	Destroy: (player: Player, houseId: string) -> (boolean, string?),
}

return HouseAttackTargetAccess
