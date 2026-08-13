--[[
	职责：把服务器权威玩家状态组合为当前新手引导快照。
	输入：已完成持久化加载的 Player。
	输出：Succeeded、StepId、CompletedVersion，以及用于诊断的权威条件值。
	内部算法：读取 R1 等级、余额、M1-S1/DM-R1 建造状态和当前建造事务后调用纯 TutorialProgression.Resolve。
	不负责：修改状态、完成引导、Remote、场景目标解析或 UI。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DefenseMonsterSpawnPointStateService = require(
	script.Parent.DefenseMonsterSpawnPointStateService
)
local IncomeZoneActionQuery = require(script.Parent.IncomeZoneActionQuery)
local MoneyService = require(script.Parent.MoneyService)
local MonsterSpawnPointActionQuery = require(script.Parent.MonsterSpawnPointActionQuery)
local MonsterSpawnPointPurchaseCoordinator = require(
	script.Parent.MonsterSpawnPointPurchaseCoordinator
)
local MonsterSpawnPointStateService = require(script.Parent.MonsterSpawnPointStateService)
local TutorialProgressStateService = require(script.Parent.TutorialProgressStateService)
local ZoneStateService = require(script.Parent.ZoneStateService)
local TutorialProgression = require(
	ReplicatedStorage.Shared.Tutorial.TutorialProgression
)
local DefenseMonsterEconomyConfigs = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterEconomyConfigs
)

local TutorialSnapshotQuery = {}

function TutorialSnapshotQuery.Query(player: Player)
	local completedVersion = TutorialProgressStateService.Get(player)
	local r1Level = ZoneStateService.GetLevel(player, "R1")
	local money = MoneyService.Get(player)
	local firstMonsterBuilt = MonsterSpawnPointStateService.Get(player, "M1-S1").Built
	local firstDefenseMonsterBuilt = DefenseMonsterSpawnPointStateService.Get(
		player,
		"DM-R1"
	).Built
	local firstMonsterBuildInProgress = not firstMonsterBuilt
		and MonsterSpawnPointPurchaseCoordinator.IsSpawnPointBusy(player, "M1-S1")
	local r1Action = assert(IncomeZoneActionQuery.Get(player, "R1"), "R1 action config missing")
	local firstMonsterAction = assert(
		MonsterSpawnPointActionQuery.Get(player, "M1-S1"),
		"M1-S1 action config missing"
	)
	local r1UpgradeCost = if r1Level == 1 then r1Action.Construction.Cost else 0
	local firstMonsterBuildCost = firstMonsterAction.Build.Cost
	local firstDefenseMonsterBuildCost = assert(
		DefenseMonsterEconomyConfigs["DM-R1"],
		"DM-R1 economy config missing"
	).BuildCost
	local stepId = TutorialProgression.Resolve({
		CompletedVersion = completedVersion,
		R1Level = r1Level,
		Money = money,
		R1UpgradeCost = r1UpgradeCost,
		FirstMonsterBuildCost = firstMonsterBuildCost,
		FirstMonsterBuilt = firstMonsterBuilt,
		FirstMonsterBuildInProgress = firstMonsterBuildInProgress,
		FirstDefenseMonsterBuildCost = firstDefenseMonsterBuildCost,
		FirstDefenseMonsterBuilt = firstDefenseMonsterBuilt,
	})
	return {
		Succeeded = true,
		StepId = stepId,
		CompletedVersion = completedVersion,
		R1Level = r1Level,
		Money = money,
		R1UpgradeCost = r1UpgradeCost,
		FirstMonsterBuildCost = firstMonsterBuildCost,
		FirstMonsterBuilt = firstMonsterBuilt,
		FirstMonsterBuildInProgress = firstMonsterBuildInProgress,
		FirstDefenseMonsterBuildCost = firstDefenseMonsterBuildCost,
		FirstDefenseMonsterBuilt = firstDefenseMonsterBuilt,
	}
end

return TutorialSnapshotQuery
