--[[
	职责：提供与 UI 形态无关的怪兽管理应用接口。

	输入：Query/Upgrade 接收 Player、SpawnPointId。
	输出：Succeeded、Reason，以及只包含 Upgrade/Attack 的最新管理快照。
	内部算法：Query 过滤现有权威操作快照；Upgrade 调用同一购买协调器后重新查询。

	不负责：Remote、GUI、目标玩家选择、攻击提交或相机。
]]

local MonsterSpawnPointActionQuery = require(script.Parent.MonsterSpawnPointActionQuery)
local MonsterSpawnPointPurchaseCoordinator = require(
	script.Parent.MonsterSpawnPointPurchaseCoordinator
)

local MonsterManagementCoordinator = {}

local function getSnapshot(player: Player, spawnPointId: string)
	local source = MonsterSpawnPointActionQuery.Get(player, spawnPointId)
	if not source then
		return nil, "UnknownSpawnPoint"
	end
	if not source.Built then
		return nil, "SpawnPointNotBuilt"
	end
	return {
		SpawnPointId = source.SpawnPointId,
		Built = source.Built,
		Level = source.Level,
		MonsterKey = source.MonsterKey,
		MonsterState = source.MonsterState,
		Balance = source.Balance,
		Upgrade = source.Upgrade,
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

return MonsterManagementCoordinator
