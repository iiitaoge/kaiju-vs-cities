--[[
	职责：把产钱 Zone 的 HouseId 映射到共享建筑模板。
	输入：无。
	输出：ZoneId → ModelRoot → GroupName → 房屋模板和建造进度配置。
	内部算法：保存稳定身份、模板路径和纯进度参数；实际布局只读取玩家 Plot 的同名 Slot。
	不负责：Workspace 放置点、玩家状态、建造、升级、经济或表现。
]]

return {
	R1 = {
		ModelRoot = "ReplicatedStorage/Buildings/Income/R1",

		Groups = {
			Left = {
				{ HouseId = "R1-H5", VariantName = "green" },
				{ HouseId = "R1-H6", VariantName = "red" },
				{ HouseId = "R1-H7", VariantName = "teal" },
				{ HouseId = "R1-H8", VariantName = "yellow" },
			},

			Right = {
				{ HouseId = "R1-H1", VariantName = "Indigo" },
				{ HouseId = "R1-H2", VariantName = "blue" },
				{ HouseId = "R1-H3", VariantName = "mauve" },
				{ HouseId = "R1-H4", VariantName = "orange" },
			},
		},
	},

	R2 = {
		ModelRoot = "ReplicatedStorage/Buildings/Income/R2",

		Groups = {
			Left = {
				{ HouseId = "R2-H5", VariantName = "green" },
				{ HouseId = "R2-H6", VariantName = "red" },
				{ HouseId = "R2-H7", VariantName = "teal" },
				{ HouseId = "R2-H8", VariantName = "yellow" },
			},

			Right = {
				{ HouseId = "R2-H1", VariantName = "Indigo" },
				{ HouseId = "R2-H2", VariantName = "blue" },
				{ HouseId = "R2-H3", VariantName = "mauve" },
				{ HouseId = "R2-H4", VariantName = "orange" },
			},
		},
	},

	R3 = {
		ModelRoot = "ReplicatedStorage/Buildings/Income/R3",

		Groups = {
			Left = {
				{ HouseId = "R3-H5", VariantName = "DarkGreen" },
				{ HouseId = "R3-H6", VariantName = "OrangeRed" },
				{ HouseId = "R3-H7", VariantName = "Yellow" },
				{ HouseId = "R3-H8", VariantName = "Blue" },
			},

			Right = {
				{ HouseId = "R3-H1", VariantName = "Indigo" },
				{ HouseId = "R3-H2", VariantName = "Violet" },
				{ HouseId = "R3-H3", VariantName = "Pink" },
				{ HouseId = "R3-H4", VariantName = "Flesh" },
			},
		},
	},

	R4 = {
		ModelRoot = "ReplicatedStorage/Buildings/Income/R4",

		Groups = {
			Waste = {
				{
					HouseId = "R4-H1",
					BuildAtRegionLevel = 2,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
				{
					HouseId = "R4-H2",
					BuildAtRegionLevel = 3,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
				{
					HouseId = "R4-H3",
					BuildAtRegionLevel = 4,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
				{
					HouseId = "R4-H4",
					BuildAtRegionLevel = 5,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
				{
					HouseId = "R4-H5",
					BuildAtRegionLevel = 6,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
				{
					HouseId = "R4-H6",
					BuildAtRegionLevel = 7,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
				{
					HouseId = "R4-H7",
					BuildAtRegionLevel = 8,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
			},

			Warehouse = {
				{
					HouseId = "R4-A1",
					BuildAtRegionLevel = 1,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 4,
				},
				{
					HouseId = "R4-A2",
					BuildAtRegionLevel = 1,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 4,
				},
			},
		},
	},

	R5 = {
		ModelRoot = "ReplicatedStorage/Buildings/Income/R5",

		Groups = {
			violet = {
				{
					HouseId = "R5-H1",
					BuildAtRegionLevel = 1,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
			},
			pink = {
				{
					HouseId = "R5-H2",
					BuildAtRegionLevel = 1,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
			},
			orange = {
				{
					HouseId = "R5-H3",
					BuildAtRegionLevel = 1,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
			},
			green = {
				{
					HouseId = "R5-H4",
					BuildAtRegionLevel = 1,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
			},
			blue = {
				{
					HouseId = "R5-H5",
					BuildAtRegionLevel = 1,
					RegionLevelsPerModelLevel = 2,
					MaxModelLevel = 3,
				},
			},
		},
	},
}
