local HouseAttackTargetAccess = {}

export type HouseTarget = {
	HouseId: string,
	RegionId: string,
	CFrame: CFrame,
	Size: Vector3,
	HealthGeneration: number,
	CurrentHealth: number,
	MaxHealth: number,
}

export type DamageResult = {
	Accepted: boolean,
	Reason: string?,
	HouseId: string,
	Level: number?,
	Generation: number?,
	PreviousHealth: number?,
	CurrentHealth: number?,
	MaxHealth: number?,
	DamageApplied: number,
	Depleted: boolean,
}

export type Access = {
	-- 输入 player；输出该玩家当前可参与攻击选择的房屋快照。
	ListAliveTargets: (player: Player) -> { HouseTarget },
	-- 输入 player、houseId；输出最新可攻击范围，失败时返回原因。
	ResolveAliveTarget: (player: Player, houseId: string) -> (HouseTarget?, string?),
	-- 输入 player、houseId、目标代次和伤害；输出原子伤害结算。
	ApplyDamage: (player: Player, houseId: string, number, number) -> DamageResult,
	-- 输入致命提交失败前的血量；仅回滚同代且仍为 0 的伤害。
	RollbackDamage: (player: Player, houseId: string, number, number) -> boolean,
	-- 输入 player、houseId；输出摧毁前业务准备是否成功及失败原因。
	PrepareDestroy: (player: Player, houseId: string) -> (boolean, string?),
	-- 输入 player、houseId；输出是否首次完成 Alive -> Destroyed 并同步运行时建筑。
	Destroy: (player: Player, houseId: string) -> (boolean, string?),
}

return HouseAttackTargetAccess
