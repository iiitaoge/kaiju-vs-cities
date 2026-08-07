--[[
	职责：保存决斗场景模板、出生点和镜头的稳定配置。
	输入：无；调用方读取只读配置。
	输出：决斗场景层级名称、运行时隔离距离和镜头参数。
	不负责：克隆场景、移动怪兽、发布网络命令或控制客户端 CurrentCamera。
]]

local camera = table.freeze({
	FieldOfView = 55,
	TransitionDuration = 1,
	CompletionTimeout = 5,
	RestoreDuration = 0.75,
})

return table.freeze({
	TemplateName = "MonsterDuelSceneTemplate",
	RuntimeFolderName = "MonsterDuelScenes",
	ArenaName = "Arena",
	AttackerSpawnPointName = "AttackMonsterSpawnPoint",
	DefenderSpawnPointName = "DefenseMonsterSlot",
	DefenderSpawnPointFallbackName = "DefenderSpawnPoint",
	CameraMarkerName = "CameraMarker",
	RuntimeSceneSpacing = 2048,
	Camera = camera,
})
