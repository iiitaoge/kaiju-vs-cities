--[[
	职责：
	- 把 Workspace/Buttons 下的按钮 Model 映射到一个 ActionId。

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
]]

-- 配置键是 Workspace/Buttons 下唯一需要登记的 Model 名称。
return {
	Region1Button1 = {
		InitialState = "Ready",
		ActionId = "R1Upgrade",
	},

	Region1Button2 = {
		InitialState = "Ready",
		ActionId = "R1Bonus",
	},
}
