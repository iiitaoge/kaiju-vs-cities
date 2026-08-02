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
	- HouseAction：
	  当前只支持 "Build"，表示这一级把该区域仍为 Unbuilt 的房屋建造成 Alive。
	  没有该字段时，升级只改变区域等级。
	- ClientAction：
	  服务端升级成功后返回客户端的表现动作；由 LocalActionController 执行。

	说明：
	- 本配置描述 UpgradeRegion 自己的效果。
	- 其他按钮 Action 不会被收入系统推断成 UpgradeRegion。
]]

return {
	R1 = {
		Levels = {
			[1] = {
				HouseAction = "Build",
				ClientAction = { Kind = "Build", JobName = "Job1" },
			},

			[2] = {
				ClientAction = { Kind = "Upgrade", JobName = "Job2" },
			},

			[3] = {
				ClientAction = { Kind = "Upgrade", JobName = "Job3" },
			},
		},
	},

	R2 = {
		Levels = {
			[1] = {
				HouseAction = "Build",
				ClientAction = { Kind = "Build", JobName = "Job4" },
			},

			[2] = {
				ClientAction = { Kind = "Upgrade", JobName = "Job5" },
			},

			[3] = {
				ClientAction = { Kind = "Upgrade", JobName = "Job6" },
			},
		},
	},
}
