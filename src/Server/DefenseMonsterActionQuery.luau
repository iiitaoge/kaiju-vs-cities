--[[
	职责：组合防守怪兽独立资产、运行时状态、经济配置和余额为操作快照。
	输入：Player、防守 SpawnPointId。
	输出：Build/Upgrade/DiamondUpgrade/Attack 权限、价格、主动作和实体建造按钮状态；Attack 永远不可用。
	内部算法：未建造时查询 Build；已建造时查询下一等级 Upgrade 或钻石满级 Upgrade。
	不负责：扣款、状态写入、模型、UI 或攻击命令。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiamondService = require(script.Parent.DiamondService)
local DefenseMonsterSpawnPointStateService = require(
	script.Parent.DefenseMonsterSpawnPointStateService
)
local MoneyService = require(script.Parent.MoneyService)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local PlayerDefenseMonsterRuntimeCoordinator = require(
	script.Parent.PlayerDefenseMonsterRuntimeCoordinator
)
local MonsterDiamondUpgradeConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterDiamondUpgradeConfigs
)
local PlayerMonsterLevelLimitQuery = require(script.Parent.PlayerMonsterLevelLimitQuery)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local DefenseMonsterEconomyConfigs = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterEconomyConfigs
)

local DefenseMonsterActionQuery = {}

local function status(allowed, reason: string?, cost: number, balance: number, targetLevel: number?)
	return {
		Allowed = allowed,
		Reason = reason,
		Cost = cost,
		Affordable = balance >= cost,
		TargetLevel = targetLevel,
	}
end

local function buttonState(action): string
	if not action.Allowed then
		return "Locked"
	end
	return if action.Affordable then "Ready" else "Insufficient"
end

function DefenseMonsterActionQuery.Get(player: Player, spawnPointId: string)
	local definition = DefenseMonsterSlotCatalog.Get(spawnPointId)
	if not definition then
		return nil
	end
	local state = DefenseMonsterSpawnPointStateService.Get(player, spawnPointId)
	local balance = MoneyService.Get(player)
	local diamondBalance = DiamondService.Get(player)
	local economy = DefenseMonsterEconomyConfigs[spawnPointId]
	local levelLimit = PlayerMonsterLevelLimitQuery.Get(player, definition.ProgressionId)
	if not levelLimit then
		return nil
	end
	local maxLevel = levelLimit.MaxLevel
	local diamondUpgradeConfig = MonsterDiamondUpgradeConfigs[definition.ProgressionId]
	if not economy or not maxLevel or not diamondUpgradeConfig then
		return nil
	end
	local buildPermission = PlayerDefenseMonsterRuntimeCoordinator.CanBuild(
		player,
		spawnPointId
	)
	local nextLevel = state.Level + 1
	local upgradeCost = economy.UpgradeCostByTargetLevel[nextLevel]
	local permission
	if not state.Built then
		permission = { Allowed = false, Reason = "DefenseMonsterNotBuilt" }
	elseif not upgradeCost then
		permission = { Allowed = false, Reason = "MaxLevel" }
	else
		permission = PlayerDefenseMonsterRuntimeCoordinator.CanUpgrade(
			player,
			spawnPointId,
			nextLevel
		)
	end
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	local build = status(
		buildPermission.Allowed,
		buildPermission.Reason,
		economy.BuildCost,
		balance,
		1
	)
	local upgrade = status(
		permission.Allowed,
		permission.Reason,
		upgradeCost or 0,
		balance,
		if upgradeCost then nextLevel else nil
	)
	local diamondUpgradePermission
	if not state.Built then
		diamondUpgradePermission = { Allowed = false, Reason = "DefenseMonsterNotBuilt" }
	elseif state.Level >= maxLevel then
		diamondUpgradePermission = {
			Allowed = false,
			Reason = if state.Level >= levelLimit.TotalMaxLevel
				then "MaxLevel"
				else "RebirthRequired",
		}
	else
		diamondUpgradePermission = PlayerDefenseMonsterRuntimeCoordinator.CanUpgrade(
			player,
			spawnPointId,
			maxLevel
		)
	end
	local diamondUpgrade = status(
		diamondUpgradePermission.Allowed,
		diamondUpgradePermission.Reason,
		diamondUpgradeConfig.MaxUpgradeCost,
		diamondBalance,
		if diamondUpgradePermission.Allowed then maxLevel else nil
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
		DiamondBalance = diamondBalance,
		Build = build,
		Upgrade = upgrade,
		DiamondUpgrade = diamondUpgrade,
		Attack = status(false, "DefenseMonsterCannotAttack", 0, balance, nil),
		PrimaryAction = primaryAction,
		PrimaryButtonState = buttonState(primaryStatus),
	}
end

function DefenseMonsterActionQuery.GetPrimaryButtonState(player: Player, spawnPointId: string): string
	local snapshot = DefenseMonsterActionQuery.Get(player, spawnPointId)
	return if snapshot then snapshot.PrimaryButtonState else "Locked"
end


function DefenseMonsterActionQuery.GetBuildButtonState(player: Player, spawnPointId: string): string
	local snapshot = DefenseMonsterActionQuery.Get(player, spawnPointId)
	if not snapshot or snapshot.Built then
		return "Locked"
	end
	return buttonState(snapshot.Build)
end

function DefenseMonsterActionQuery.GetDiamondUpgradeButtonState(
	player: Player,
	spawnPointId: string
): string
	local snapshot = DefenseMonsterActionQuery.Get(player, spawnPointId)
	return if snapshot then buttonState(snapshot.DiamondUpgrade) else "Locked"
end

return DefenseMonsterActionQuery
