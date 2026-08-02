--[[
	职责：
	- 把 ButtonConfigs.ActionId 映射为服务端业务动作。

	输入：
	- 无。

	输出：
	- 以 ActionId 为键的只读动作配置。

	读取模块：
	- ButtonService。

	写入模块：
	- 无。运行时模块不得修改本配置。

	通用字段：
	- RunOn：动作在 "Server" 或 "Client" 执行。
	- Kind：ButtonActionExecutor 或 LocalActionController 的处理器键。
	- Repeat：true 表示每次踩按钮都重复当前动作。

	动作字段：
	- UnlockRegion / UpgradeRegion：RegionId。
	- SetIncomeMultiplier：RegionId、Value。
	- MonsterSpawnPointPrimary：SpawnPointId；未建造时建造，已建造时升级。
]]

-- 配置键是 ButtonConfigs 中引用的 ActionId，与 Studio Model 名称无关。
return {
	R1Upgrade = {
		{ RunOn = "Server", Kind = "UpgradeRegion", RegionId = "R1", Repeat = true },
	},

	R1Bonus = {
		{ RunOn = "Server", Kind = "SetIncomeMultiplier", RegionId = "R1", Value = 2 },
	},

	M1S1Primary = {
		{
			RunOn = "Server",
			Kind = "MonsterSpawnPointPrimary",
			SpawnPointId = "M1-S1",
			Repeat = true,
		},
	},
}
