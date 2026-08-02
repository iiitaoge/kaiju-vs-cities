--[[
	职责：把出生点状态、怪兽状态、运行时环境和经济配置组合成无副作用的可用操作快照。

	输入：Player、SpawnPointId。
	输出：Build、Upgrade、Attack 的 Allowed/Reason/Cost/Affordable，以及主按钮状态。
	内部算法：调用运行时预检查，读取余额，并由 Built 决定主按钮当前代表 Build 还是 Upgrade。

	不负责：扣款、修改状态、创建模型、发送 Remote 或播放表现。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneyService = require(script.Parent.MoneyService)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterSpawnPointStateService = require(script.Parent.MonsterSpawnPointStateService)
local PlayerMonsterRuntimeCoordinator = require(script.Parent.PlayerMonsterRuntimeCoordinator)
local MonsterSpawnPointCatalog = require(ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog)
local MonsterSpawnPointEconomyConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointEconomyConfigs
)
local MonsterStateRules = require(ReplicatedStorage.Shared.Monster.MonsterStateRules)

local MonsterSpawnPointActionQuery = {}

export type ActionStatus = {
	Allowed: boolean,
	Reason: string?,
	Cost: number,
	Affordable: boolean,
	TargetLevel: number?,
}

export type Snapshot = {
	SpawnPointId: string,
	Built: boolean,
	Level: number,
	MonsterKey: string?,
	MonsterState: string?,
	Balance: number,
	Build: ActionStatus,
	Upgrade: ActionStatus,
	Attack: ActionStatus,
	PrimaryAction: "Build" | "Upgrade",
	PrimaryButtonState: string,
}

local function status(
	allowed: boolean,
	reason: string?,
	cost: number,
	balance: number,
	targetLevel: number?
): ActionStatus
	return {
		Allowed = allowed,
		Reason = reason,
		Cost = cost,
		Affordable = balance >= cost,
		TargetLevel = targetLevel,
	}
end

local function buttonState(action: ActionStatus): string
	if not action.Allowed then
		return "Locked"
	end
	return if action.Affordable then "Ready" else "Insufficient"
end

function MonsterSpawnPointActionQuery.Get(player: Player, spawnPointId: string): Snapshot?
	if not MonsterSpawnPointCatalog.Get(spawnPointId) then
		return nil
	end
	local economy = MonsterSpawnPointEconomyConfigs[spawnPointId]
	if not economy then
		return nil
	end

	local state = MonsterSpawnPointStateService.Get(player, spawnPointId)
	local balance = MoneyService.Get(player)
	local buildPermission = PlayerMonsterRuntimeCoordinator.CanBuild(player, spawnPointId)
	local nextLevel = state.Level + 1
	local upgradeCost = economy.UpgradeCostByTargetLevel[nextLevel]
	local upgradePermission
	if not state.Built then
		upgradePermission = { Allowed = false, Reason = "SpawnPointNotBuilt" }
	elseif not upgradeCost then
		upgradePermission = { Allowed = false, Reason = "MaxLevel" }
	else
		upgradePermission = PlayerMonsterRuntimeCoordinator.CanUpgrade(
			player,
			spawnPointId,
			nextLevel
		)
	end

	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	local attackPermission
	if not state.Built then
		attackPermission = { Allowed = false, Reason = "SpawnPointNotBuilt" }
	elseif not record then
		attackPermission = { Allowed = false, Reason = "MonsterUnavailable" }
	else
		attackPermission = MonsterStateRules.CheckAttack(record.State)
	end

	local build = status(
		buildPermission.Allowed,
		buildPermission.Reason,
		economy.BuildCost,
		balance,
		1
	)
	local upgrade = status(
		upgradePermission.Allowed,
		upgradePermission.Reason,
		upgradeCost or 0,
		balance,
		if upgradeCost then nextLevel else nil
	)
	local attack = status(
		attackPermission.Allowed,
		attackPermission.Reason,
		0,
		balance,
		nil
	)
	local primaryAction = if state.Built then "Upgrade" else "Build"
	local primaryStatus = if primaryAction == "Build" then build else upgrade

	return {
		SpawnPointId = spawnPointId,
		Built = state.Built,
		Level = state.Level,
		MonsterKey = state.MonsterKey,
		MonsterState = if record then record.State else nil,
		Balance = balance,
		Build = build,
		Upgrade = upgrade,
		Attack = attack,
		PrimaryAction = primaryAction,
		PrimaryButtonState = buttonState(primaryStatus),
	}
end

function MonsterSpawnPointActionQuery.GetPrimaryButtonState(
	player: Player,
	spawnPointId: string
): string
	local snapshot = MonsterSpawnPointActionQuery.Get(player, spawnPointId)
	return if snapshot then snapshot.PrimaryButtonState else "Locked"
end

return MonsterSpawnPointActionQuery
