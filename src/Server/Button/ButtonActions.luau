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
	- Kind：ButtonActionExecutor 的服务器处理器键。
	- Repeat：true 表示每次踩按钮都重复当前动作。

	动作字段：
	- IncomeZoneUnlock：RegionId；只负责解锁，不建造房屋。
	- IncomeZonePrimary：RegionId；只负责建造或升级。
	- IncomeZoneBoost：RegionId；一次性开启收入/生命翻倍和自动收入。
	- MonsterSpawnPointBuild：SpawnPointId；只负责首次建造，升级由培养罐 UI 请求。
	- DefenseMonsterBuild：SpawnPointId；只负责首次建造，升级由怪兽 UI 请求。
]]

-- 配置键是 ButtonConfigs 中引用的 ActionId，与 Studio Model 名称无关。
return {
	R1Primary = {
		{ RunOn = "Server", Kind = "IncomeZonePrimary", RegionId = "R1", Repeat = true },
	},

	R2Primary = {
		{ RunOn = "Server", Kind = "IncomeZonePrimary", RegionId = "R2", Repeat = true },
	},

	R3Primary = {
		{ RunOn = "Server", Kind = "IncomeZonePrimary", RegionId = "R3", Repeat = true },
	},

	R3Unlock = {
		{ RunOn = "Server", Kind = "IncomeZoneUnlock", RegionId = "R3", Repeat = true },
	},
	R4Unlock = {
		{ RunOn = "Server", Kind = "IncomeZoneUnlock", RegionId = "R4", Repeat = true },
	},
	R5Unlock = {
		{ RunOn = "Server", Kind = "IncomeZoneUnlock", RegionId = "R5", Repeat = true },
	},
	R6Unlock = {
		{ RunOn = "Server", Kind = "IncomeZoneUnlock", RegionId = "R6", Repeat = true },
	},

	R1Upgrade = {
		{ RunOn = "Server", Kind = "IncomeZonePrimary", RegionId = "R1", Repeat = true },
	},
	R1Boost = {
		{ RunOn = "Server", Kind = "IncomeZoneBoost", RegionId = "R1", Repeat = true },
	},
	R2Upgrade = {
		{ RunOn = "Server", Kind = "IncomeZonePrimary", RegionId = "R2", Repeat = true },
	},
	R2Boost = {
		{ RunOn = "Server", Kind = "IncomeZoneBoost", RegionId = "R2", Repeat = true },
	},
	R3Upgrade = {
		{ RunOn = "Server", Kind = "IncomeZonePrimary", RegionId = "R3", Repeat = true },
	},
	R3Boost = {
		{ RunOn = "Server", Kind = "IncomeZoneBoost", RegionId = "R3", Repeat = true },
	},
	R4Upgrade = {
		{ RunOn = "Server", Kind = "IncomeZonePrimary", RegionId = "R4", Repeat = true },
	},
	R4Boost = {
		{ RunOn = "Server", Kind = "IncomeZoneBoost", RegionId = "R4", Repeat = true },
	},
	R5Upgrade = {
		{ RunOn = "Server", Kind = "IncomeZonePrimary", RegionId = "R5", Repeat = true },
	},
	R5Boost = {
		{ RunOn = "Server", Kind = "IncomeZoneBoost", RegionId = "R5", Repeat = true },
	},
	R6Upgrade = {
		{ RunOn = "Server", Kind = "IncomeZonePrimary", RegionId = "R6", Repeat = true },
	},
	R6Boost = {
		{ RunOn = "Server", Kind = "IncomeZoneBoost", RegionId = "R6", Repeat = true },
	},

	DMR1Build = {
		{ RunOn = "Server", Kind = "DefenseMonsterBuild", SpawnPointId = "DM-R1", Repeat = true },
	},
	DMR2Build = {
		{ RunOn = "Server", Kind = "DefenseMonsterBuild", SpawnPointId = "DM-R2", Repeat = true },
	},
	DMR3Build = {
		{ RunOn = "Server", Kind = "DefenseMonsterBuild", SpawnPointId = "DM-R3", Repeat = true },
	},
	DMR4Build = {
		{ RunOn = "Server", Kind = "DefenseMonsterBuild", SpawnPointId = "DM-R4", Repeat = true },
	},
	DMR5Build = {
		{ RunOn = "Server", Kind = "DefenseMonsterBuild", SpawnPointId = "DM-R5", Repeat = true },
	},
	DMR6Build = {
		{ RunOn = "Server", Kind = "DefenseMonsterBuild", SpawnPointId = "DM-R6", Repeat = true },
	},

	M1S1Build = {
		{
			RunOn = "Server",
			Kind = "MonsterSpawnPointBuild",
			SpawnPointId = "M1-S1",
			Repeat = true,
		},
	},
	M1S2Build = {
		{
			RunOn = "Server",
			Kind = "MonsterSpawnPointBuild",
			SpawnPointId = "M1-S2",
			Repeat = true,
		},
	},
	M1S3Build = {
		{
			RunOn = "Server",
			Kind = "MonsterSpawnPointBuild",
			SpawnPointId = "M1-S3",
			Repeat = true,
		},
	},
	M1S4Build = {
		{
			RunOn = "Server",
			Kind = "MonsterSpawnPointBuild",
			SpawnPointId = "M1-S4",
			Repeat = true,
		},
	},
}
