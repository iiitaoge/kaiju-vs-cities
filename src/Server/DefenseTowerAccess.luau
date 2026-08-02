local DefenseTowerAccess = {}

export type TowerTarget = {
	TowerId: string,
	Position: Vector3,
	Range: number,
	Damage: number,
	AttackInterval: number,
	Active: boolean,
}

export type Access = {
	-- 输入防守玩家；输出当前可参与自动防守的服务器权威防御塔快照。
	ListAliveTowers: (Player) -> { TowerTarget },
}

return DefenseTowerAccess
