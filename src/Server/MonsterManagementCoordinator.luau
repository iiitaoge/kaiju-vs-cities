--[[
	职责：提供与 UI 形态无关的怪兽管理应用接口。

	输入：Query/Upgrade/UpgradeToMax 接收 Player、SpawnPointId。
	输出：Succeeded、Reason，以及包含金币逐级升级、钻石满级升级和 Attack 的最新快照。
	内部算法：Query 过滤现有权威操作快照；两种升级都调用同一购买协调器后重新查询。

	不负责：Remote、GUI、目标玩家选择、攻击提交或相机。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DefenseMonsterActionQuery = require(script.Parent.DefenseMonsterActionQuery)
local MonsterSpawnPointActionQuery = require(script.Parent.MonsterSpawnPointActionQuery)
local MonsterSpawnPointPurchaseCoordinator = require(
	script.Parent.MonsterSpawnPointPurchaseCoordinator
)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)
local PaidProductCatalog = require(ReplicatedStorage.Shared.Monetization.PaidProductCatalog)
local PlayerMonsterRuntimeCoordinator = require(script.Parent.PlayerMonsterRuntimeCoordinator)
local PlayerDefenseMonsterRuntimeCoordinator = require(
	script.Parent.PlayerDefenseMonsterRuntimeCoordinator
)
local PlayerMonsterLevelLimitQuery = require(script.Parent.PlayerMonsterLevelLimitQuery)

local MonsterManagementCoordinator = {}

local function getSnapshot(player: Player, spawnPointId: string)
	local source = if DefenseMonsterSlotCatalog.Get(spawnPointId)
		then DefenseMonsterActionQuery.Get(player, spawnPointId)
		else MonsterSpawnPointActionQuery.Get(player, spawnPointId)
	if not source then
		return nil, "UnknownSpawnPoint"
	end
	if not source.Built then
		return nil, "SpawnPointNotBuilt"
	end
	local robuxProductId = PaidProductCatalog.GetMonsterUpgradeToMaxProductId()
	local configuredTarget = PaidProductCatalog.GetMonsterUpgradeTargetLevel()
	local progressionId = if DefenseMonsterSlotCatalog.Get(spawnPointId)
		then assert(DefenseMonsterSlotCatalog.Get(spawnPointId)).ProgressionId
		else assert(MonsterSpawnPointCatalog.Get(spawnPointId)).ProgressionId
	local levelLimit = PlayerMonsterLevelLimitQuery.Get(player, progressionId)
	local maxLevel = levelLimit and levelLimit.MaxLevel
	local targetLevel = if configuredTarget == "Max"
		then maxLevel
		else configuredTarget
	local paidPermission
	if type(targetLevel) ~= "number" then
		paidPermission = { Allowed = false, Reason = "TargetLevelUnavailable" }
	elseif source.Level >= targetLevel then
		paidPermission = {
			Allowed = false,
			Reason = if configuredTarget == "Max"
				and levelLimit
				and levelLimit.MaxLevel < levelLimit.TotalMaxLevel
			then "RebirthRequired"
			else "TargetLevelReached",
			TargetLevel = targetLevel,
		}
	elseif targetLevel == source.DiamondUpgrade.TargetLevel then
		paidPermission = source.DiamondUpgrade
	elseif DefenseMonsterSlotCatalog.Get(spawnPointId) then
		paidPermission = PlayerDefenseMonsterRuntimeCoordinator.CanUpgrade(
			player,
			spawnPointId,
			targetLevel
		)
	else
		paidPermission = PlayerMonsterRuntimeCoordinator.CanUpgrade(
			player,
			spawnPointId,
			targetLevel
		)
	end
	local robuxUpgrade = {
		Allowed = paidPermission.Allowed == true,
		Reason = paidPermission.Reason,
		Cost = 0,
		Affordable = robuxProductId > 0,
		TargetLevel = targetLevel,
		ProductId = robuxProductId,
	}
	if robuxProductId <= 0 then
		robuxUpgrade.Allowed = false
		robuxUpgrade.Reason = "ProductNotConfigured"
	end
	return {
		SpawnPointId = source.SpawnPointId,
		Built = source.Built,
		Level = source.Level,
		MonsterKey = source.MonsterKey,
		MonsterState = source.MonsterState,
		Balance = source.Balance,
		DiamondBalance = source.DiamondBalance,
		Upgrade = source.Upgrade,
		DiamondUpgrade = source.DiamondUpgrade,
		RobuxUpgrade = robuxUpgrade,
		Attack = source.Attack,
	}, nil
end

local function response(succeeded: boolean, reason: string?, snapshot)
	return {
		Succeeded = succeeded,
		Reason = reason,
		Snapshot = snapshot,
	}
end

function MonsterManagementCoordinator.Query(player: Player, spawnPointId: string)
	local snapshot, reason = getSnapshot(player, spawnPointId)
	return response(snapshot ~= nil, reason, snapshot)
end

function MonsterManagementCoordinator.Upgrade(player: Player, spawnPointId: string)
	local purchase = MonsterSpawnPointPurchaseCoordinator.Upgrade(player, spawnPointId)
	local snapshot, snapshotReason = getSnapshot(player, spawnPointId)
	return response(
		purchase.Succeeded,
		purchase.Reason or snapshotReason,
		snapshot
	)
end

function MonsterManagementCoordinator.UpgradeToMax(player: Player, spawnPointId: string)
	local purchase = MonsterSpawnPointPurchaseCoordinator.UpgradeToMax(player, spawnPointId)
	local snapshot, snapshotReason = getSnapshot(player, spawnPointId)
	return response(
		purchase.Succeeded,
		purchase.Reason or snapshotReason,
		snapshot
	)
end

return MonsterManagementCoordinator
