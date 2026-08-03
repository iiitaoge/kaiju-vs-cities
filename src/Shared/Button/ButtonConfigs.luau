--[[
	职责：
	- 把按钮 Model 映射到 ActionId 和场景作用域。

	输入：
	- 无。

	输出：
	- 以按钮 Model 名称为键的只读配置。

	读取模块：
	- 客户端 ButtonController。
	- 服务端 ButtonService。

	写入模块：
	- 无。运行时模块不得修改本配置。

	字段：
	- InitialState：客户端首次绑定时显示的颜色状态，不是服务端权限。
	- ActionId：ButtonActions 中的业务动作键。
	- Scope：Global 表示 Workspace/Buttons；PlayerPlot 表示玩家 Plot 的 Zone/Buttons。
	- ZoneId：PlayerPlot 按钮所在 Zone。
	- MaxActivationDistance：服务端允许触发的最大距离。
]]

return {
	-- 旧 Plot 过渡入口；Plot02～Plot06 场景迁移完成后删除。
	["R1-Primary-Button"] = {
		InitialState = "Locked",
		ActionId = "R1Primary",
		Scope = "PlayerPlot",
		ZoneId = "R1",
		MaxActivationDistance = 12,
	},

	["R2-Primary-Button"] = {
		InitialState = "Locked",
		ActionId = "R2Primary",
		Scope = "PlayerPlot",
		ZoneId = "R2",
		MaxActivationDistance = 12,
	},

	["R3-Primary-Button"] = {
		InitialState = "Locked",
		ActionId = "R3Primary",
		Scope = "PlayerPlot",
		ZoneId = "R3",
		MaxActivationDistance = 12,
	},

	["R1-Upgrade-Button"] = {
		InitialState = "Locked",
		ActionId = "R1Upgrade",
		Scope = "PlayerPlot",
		ZoneId = "R1",
		MaxActivationDistance = 12,
	},

	["R1-Boost-Button"] = {
		InitialState = "Locked",
		ActionId = "R1Boost",
		Scope = "PlayerPlot",
		ZoneId = "R1",
		MaxActivationDistance = 12,
	},

	["R2-Upgrade-Button"] = {
		InitialState = "Locked",
		ActionId = "R2Upgrade",
		Scope = "PlayerPlot",
		ZoneId = "R2",
		MaxActivationDistance = 12,
	},

	["R2-Boost-Button"] = {
		InitialState = "Locked",
		ActionId = "R2Boost",
		Scope = "PlayerPlot",
		ZoneId = "R2",
		MaxActivationDistance = 12,
	},

	["R3-Upgrade-Button"] = {
		InitialState = "Locked",
		ActionId = "R3Upgrade",
		Scope = "PlayerPlot",
		ZoneId = "R3",
		MaxActivationDistance = 12,
	},

	["R3-Boost-Button"] = {
		InitialState = "Locked",
		ActionId = "R3Boost",
		Scope = "PlayerPlot",
		ZoneId = "R3",
		MaxActivationDistance = 12,
	},

	["R4-Upgrade-Button"] = {
		InitialState = "Locked",
		ActionId = "R4Upgrade",
		Scope = "PlayerPlot",
		ZoneId = "R4",
		MaxActivationDistance = 12,
	},

	["R4-Boost-Button"] = {
		InitialState = "Locked",
		ActionId = "R4Boost",
		Scope = "PlayerPlot",
		ZoneId = "R4",
		MaxActivationDistance = 12,
	},

	["R5-Upgrade-Button"] = {
		InitialState = "Locked",
		ActionId = "R5Upgrade",
		Scope = "PlayerPlot",
		ZoneId = "R5",
		MaxActivationDistance = 12,
	},

	["R5-Boost-Button"] = {
		InitialState = "Locked",
		ActionId = "R5Boost",
		Scope = "PlayerPlot",
		ZoneId = "R5",
		MaxActivationDistance = 12,
	},

	["M1-S1-Button"] = {
		InitialState = "Locked",
		ActionId = "M1S1Primary",
		Scope = "PlayerPlot",
		ZoneId = "M1",
		MaxActivationDistance = 12,
	},
}
