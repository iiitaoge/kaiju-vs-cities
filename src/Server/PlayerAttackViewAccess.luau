local PlayerAttackViewAccess = {}

export type AttackView = {
	CFrame: CFrame,
	Size: Vector3,
}

export type Access = {
	-- 输入玩家；输出该玩家整个 Plot 的单一攻击相机取景范围。
	GetAttackView: (Player) -> AttackView?,
}

return PlayerAttackViewAccess
