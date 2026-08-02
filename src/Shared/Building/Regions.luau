-- 地区和房屋的稳定身份配置。
-- RegionId、HouseId 一旦投入使用就不要修改；列表顺序和分组可以调整。
return {
	R1 = {
		ModelRoot = "ReplicatedStorage/Buildings/level1",
		PointRoot = "Workspace/BuildPoint1",

		Groups = {
			Left = {
				{ HouseId = "R1-H5", VariantName = "green", PointName = "Point05" },
				{ HouseId = "R1-H6", VariantName = "red", PointName = "Point06" },
				{ HouseId = "R1-H7", VariantName = "teal", PointName = "Point07" },
				{ HouseId = "R1-H8", VariantName = "yellow", PointName = "Point08" },
			},

			Right = {
				{ HouseId = "R1-H1", VariantName = "Indigo", PointName = "Point01" },
				{ HouseId = "R1-H2", VariantName = "blue", PointName = "Point02" },
				{ HouseId = "R1-H3", VariantName = "mauve", PointName = "Point03" },
				{ HouseId = "R1-H4", VariantName = "orange", PointName = "Point04" },
			},
		},
	},

	R2 = {
		ModelRoot = "ReplicatedStorage/Buildings/level2",
		PointRoot = "Workspace/BuildPoint2",

		Groups = {
			Left = {
				{ HouseId = "R2-H5", VariantName = "green", PointName = "Point05" },
				{ HouseId = "R2-H6", VariantName = "red", PointName = "Point06" },
				{ HouseId = "R2-H7", VariantName = "teal", PointName = "Point07" },
				{ HouseId = "R2-H8", VariantName = "yellow", PointName = "Point08" },
			},

			Right = {
				{ HouseId = "R2-H1", VariantName = "Indigo", PointName = "Point01" },
				{ HouseId = "R2-H2", VariantName = "blue", PointName = "Point02" },
				{ HouseId = "R2-H3", VariantName = "mauve", PointName = "Point03" },
				{ HouseId = "R2-H4", VariantName = "orange", PointName = "Point04" },
			},
		},
	},
}
