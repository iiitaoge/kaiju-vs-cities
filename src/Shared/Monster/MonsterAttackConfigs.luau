return {
	P1 = {
		StructureDamage = 35,
		-- NearbyHouseTargetSelector 的输入参数；Radius 是双方水平包围盒的最大检测间距。
		Detection = {
			Radius = 30,
		},
		-- HouseAttackGeometry 与 HouseAttackCommitService 的输入参数。
		Geometry = {
			DesiredGap = 1,
			MaxGap = 3,
		},
		-- AttackAnimationSelector 与 AttackAnimationPlayer 的输入参数。
		Animation = {
			SelectionMode = "Sequence",
			HitProgress = 0.65,
			Speed = 1,
		},
	},

	P4 = {
		StructureDamage = 60,
		-- NearbyHouseTargetSelector 的输入参数；Radius 是双方水平包围盒的最大检测间距。
		Detection = {
			Radius = 30,
		},
		-- HouseAttackGeometry 与 HouseAttackCommitService 的输入参数。
		Geometry = {
			DesiredGap = 1,
			MaxGap = 3,
		},
		-- AttackAnimationSelector 与 AttackAnimationPlayer 的输入参数。
		Animation = {
			SelectionMode = "Sequence",
			HitProgress = 0.65,
			Speed = 1,
		},
	},
}
