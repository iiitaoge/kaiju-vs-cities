--[[
	职责：
	- 描述 UpgradeRegion 动作在每个目标等级需要执行的配置效果。

	输入：
	- 无。

	输出：
	- 以 RegionId 为键、Level 为次级键的只读配置。

	读取模块：
	- RegionUpgradeService。

	写入模块：
	- 无。运行时模块不得修改本配置。

	字段：
	- PresentationId：
	  升级提交并刷新服务器建筑后，选择 Shared.Building.BuildingPresentationConfigs
	  中的一套纯表现参数。

	说明：
	- 本配置描述 UpgradeRegion 自己的效果。
	- 其他按钮 Action 不会被收入系统推断成 UpgradeRegion。
]]

return {
	R1 = {
		Levels = {
			[1] = {
				PresentationId = "Standard",
			},

			[2] = {
				PresentationId = "Standard",
			},

			[3] = {
				PresentationId = "Standard",
			},
		},
	},

	R2 = {
		Levels = {
			[1] = {
				PresentationId = "Standard",
			},

			[2] = {
				PresentationId = "Standard",
			},

			[3] = {
				PresentationId = "Standard",
			},
		},
	},

	R3 = {
		Levels = {
			[1] = {
				PresentationId = "Standard",
			},

			[2] = {
				PresentationId = "Standard",
			},

			[3] = {
				PresentationId = "Standard",
			},
		},
	},

	R4 = {
		Levels = {
			[1] = { PresentationId = "Standard" },
			[2] = { PresentationId = "Standard" },
			[3] = { PresentationId = "Standard" },
			[4] = { PresentationId = "Standard" },
			[5] = { PresentationId = "Standard" },
			[6] = { PresentationId = "Standard" },
			[7] = { PresentationId = "Standard" },
			[8] = { PresentationId = "Standard" },
		},
	},

	R5 = {
		Levels = {
			[1] = { PresentationId = "Standard" },
			[2] = { PresentationId = "Standard" },
			[3] = { PresentationId = "Standard" },
			[4] = { PresentationId = "Standard" },
			[5] = { PresentationId = "Standard" },
			[6] = { PresentationId = "Standard" },
		},
	},
}
