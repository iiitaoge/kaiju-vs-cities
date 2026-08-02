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
	Region1Button1 = {
		InitialState = "Ready",
		ActionId = "R1Upgrade",
		Scope = "Global",
	},

	Region1Button2 = {
		InitialState = "Ready",
		ActionId = "R1Bonus",
		Scope = "Global",
	},

	["M1-S1-Button"] = {
		InitialState = "Locked",
		ActionId = "M1S1Primary",
		Scope = "PlayerPlot",
		ZoneId = "M1",
		MaxActivationDistance = 12,
	},
}
