local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManagementStateMachine = require(
	ReplicatedStorage.Shared.Monster.MonsterManagementStateMachine
)

local MonsterManagementStateMachineSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "MonsterManagementStateMachineSpec: " .. message)
end

local function snapshot(upgradeAllowed: boolean, affordable: boolean, attackAllowed: boolean)
	return {
		SpawnPointId = "M1-S1",
		Built = true,
		Level = 1,
		MonsterKey = "Godzilla-L001",
		MonsterState = "IdleAtSpawn",
		Balance = if affordable then 1000 else 0,
		DiamondBalance = 2000,
		Upgrade = {
			Allowed = upgradeAllowed,
			Reason = if upgradeAllowed then nil else "MonsterBusy",
			Cost = 1000,
			Affordable = affordable,
			TargetLevel = 2,
		},
		DiamondUpgrade = {
			Allowed = true,
			Reason = nil,
			Cost = 2000,
			Affordable = true,
			TargetLevel = 75,
		},
		RobuxUpgrade = {
			Allowed = true,
			Reason = nil,
			Cost = 0,
			Affordable = true,
			TargetLevel = 75,
			ProductId = 123,
		},
		Attack = {
			Allowed = attackAllowed,
			Reason = if attackAllowed then nil else "MonsterBusy",
			Cost = 0,
			Affordable = true,
			TargetLevel = nil,
		},
	}
end

function MonsterManagementStateMachineSpec.Run(): boolean
	local current = MonsterManagementStateMachine.New()
	local opened = MonsterManagementStateMachine.Apply(current, {
		Kind = "Open",
		SpawnPointId = "M1-S1",
	})
	expect(opened.Accepted and opened.State.Mode == "Loading", "Open 应进入 Loading")
	expect(opened.Effect and opened.Effect.Kind == "QuerySnapshot", "Open 应请求快照")

	local loaded = MonsterManagementStateMachine.Apply(opened.State, {
		Kind = "SnapshotLoaded",
		Snapshot = snapshot(true, false, true),
	})
	expect(loaded.State.Mode == "Managing", "加载后应进入 Managing")
	local diamondUpgrading = MonsterManagementStateMachine.Apply(loaded.State, {
		Kind = "ChooseDiamondUpgrade",
	})
	expect(diamondUpgrading.State.Mode == "Upgrading", "钻石满级升级应进入 Upgrading")
	expect(
		diamondUpgrading.Effect and diamondUpgrading.Effect.Kind == "RequestMaxUpgrade",
		"钻石满级升级 Effect 错误"
	)

	local insufficient = MonsterManagementStateMachine.Apply(loaded.State, {
		Kind = "ChooseUpgrade",
	})
	expect(not insufficient.Accepted, "余额不足时不应进入 Upgrading")
	expect(insufficient.Reason == "InsufficientMoney", "余额不足原因错误")

	local balanceChanged = MonsterManagementStateMachine.Apply(insufficient.State, {
		Kind = "BalanceChanged",
		Balance = 1000,
	})
	expect(balanceChanged.State.Mode == "Managing", "余额变化不应关闭管理面板")
	expect(balanceChanged.State.Snapshot.Balance == 1000, "余额快照没有更新")
	expect(balanceChanged.State.Snapshot.Upgrade.Affordable, "余额足够后升级没有变为可用")
	expect(
		not insufficient.State.Snapshot.Upgrade.Affordable,
		"余额变化不应修改旧快照"
	)
	local upgrading = MonsterManagementStateMachine.Apply(balanceChanged.State, {
		Kind = "ChooseUpgrade",
	})
	expect(upgrading.State.Mode == "Upgrading", "允许升级时应进入 Upgrading")
	expect(upgrading.Effect and upgrading.Effect.Kind == "RequestUpgrade", "升级 Effect 错误")

	local upgradedSnapshot = snapshot(false, false, true)
	upgradedSnapshot.Level = 2
	upgradedSnapshot.MonsterKey = "Godzilla-L002"
	upgradedSnapshot.Upgrade.Reason = "MaxLevel"
	local upgraded = MonsterManagementStateMachine.Apply(upgrading.State, {
		Kind = "UpgradeResolved",
		Succeeded = true,
		Snapshot = upgradedSnapshot,
	})
	expect(upgraded.State.Mode == "Managing", "升级完成后应回到 Managing")
	expect(upgraded.State.Snapshot.Level == 2, "升级完成后快照未刷新")

	local attacking = MonsterManagementStateMachine.Apply(upgraded.State, {
		Kind = "ChooseAttack",
	})
	expect(attacking.State.Mode == "SelectingAttack", "进攻应进入 SelectingAttack")
	expect(
		attacking.Effect and attacking.Effect.Kind == "OpenAttackSelection",
		"进攻 Effect 错误"
	)

	local cancelled = MonsterManagementStateMachine.Apply(attacking.State, {
		Kind = "AttackCancelled",
	})
	expect(cancelled.State.Mode == "Managing", "取消进攻应回到 Managing")

	local reopenedAttack = MonsterManagementStateMachine.Apply(cancelled.State, {
		Kind = "ChooseAttack",
	})
	local blockedOpen = MonsterManagementStateMachine.Apply(reopenedAttack.State, {
		Kind = "Open",
		SpawnPointId = "M1-S2",
	})
	expect(not blockedOpen.Accepted and blockedOpen.Reason == "AttackSelectionActive", "进攻选择中不应切换出生点")
	local accepted = MonsterManagementStateMachine.Apply(reopenedAttack.State, {
		Kind = "AttackAccepted",
	})
	expect(accepted.State.Mode == "Closed", "进攻命令接受后管理面板应关闭")
	return true
end

return MonsterManagementStateMachineSpec
