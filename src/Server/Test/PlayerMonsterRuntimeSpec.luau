local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneyService = require(script.Parent.Parent.MoneyService)
local MonsterRosterCoordinator = require(script.Parent.Parent.MonsterRosterCoordinator)
local MonsterSpawnPointActionQuery = require(script.Parent.Parent.MonsterSpawnPointActionQuery)
local MonsterSpawnPointPurchaseCoordinator = require(
	script.Parent.Parent.MonsterSpawnPointPurchaseCoordinator
)
local MonsterSpawnPointStateService = require(script.Parent.Parent.MonsterSpawnPointStateService)
local PlayerMonsterRuntimeCoordinator = require(script.Parent.Parent.PlayerMonsterRuntimeCoordinator)
local PlayerPlotAssignmentService = require(script.Parent.Parent.PlayerPlotAssignmentService)
local PlotButtonAccess = require(script.Parent.Parent.Button.PlotButtonAccess)
local MonsterSpawnPointEconomyConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointEconomyConfigs
)

local PlayerMonsterRuntimeSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "PlayerMonsterRuntimeSpec: " .. message)
end

-- 输入：已经完成 Plot 和怪兽运行时加载的测试玩家。
-- 输出：容量/余额拒绝、购买扣款、玩家 Plot 归属、升级和重载全部通过时返回 true。
-- 内部算法：依次覆盖 Locked → Insufficient → Ready → Insufficient → Ready → Locked。
function PlayerMonsterRuntimeSpec.Run(player: Player): boolean
	local economy = MonsterSpawnPointEconomyConfigs["M1-S1"]
	local buildCost = economy.BuildCost
	local upgradeCost = economy.UpgradeCostByTargetLevel[2]

	local initialBalance = MoneyService.Get(player)
	if initialBalance > 0 then
		expect(MoneyService.TrySpend(player, initialBalance).Succeeded, "无法清空测试余额")
	end

	expect(MonsterRosterCoordinator.SetCapacity(player, 0).Succeeded, "无法设置测试容量 0")
	local rejected = MonsterSpawnPointPurchaseCoordinator.Build(player, "M1-S1")
	expect(not rejected.Succeeded, "容量为 0 时不应允许建造")
	expect(rejected.Reason == "CapacityReached", "容量拒绝原因错误：" .. tostring(rejected.Reason))
	expect(rejected.Balance == 0, "容量拒绝后不应扣款")
	expect(rejected.NextButtonState == "Locked", "容量拒绝时按钮应为 Locked")
	expect(
		not MonsterSpawnPointStateService.Get(player, "M1-S1").Built,
		"被容量拒绝后不应写入 Built"
	)

	expect(MonsterRosterCoordinator.SetCapacity(player, 1).Succeeded, "无法恢复测试容量 1")
	local noBuildMoney = MonsterSpawnPointPurchaseCoordinator.Build(player, "M1-S1")
	expect(not noBuildMoney.Succeeded, "余额不足时不应允许建造")
	expect(noBuildMoney.Reason == "InsufficientMoney", "建造余额拒绝原因错误")
	expect(noBuildMoney.NextButtonState == "Insufficient", "余额不足时按钮应为 Insufficient")

	MoneyService.Add(player, buildCost)
	expect(
		MonsterSpawnPointActionQuery.GetPrimaryButtonState(player, "M1-S1") == "Ready",
		"余额充足时建造按钮应为 Ready"
	)
	local built = MonsterSpawnPointPurchaseCoordinator.ExecutePrimary(player, "M1-S1")
	expect(built.Succeeded, "建造失败：" .. tostring(built.Reason))
	expect(built.Action == "Build" and built.Cost == buildCost and built.Balance == 0, "建造扣款错误")
	expect(built.NextButtonState == "Insufficient", "建造后升级余额不足应为 Insufficient")
	expect(built.Record ~= nil and built.Record.Model ~= nil, "建造成功后缺少运行时模型")

	local plot = PlayerPlotAssignmentService.GetPlot(player)
	expect(plot ~= nil, "玩家没有 Plot")
	expect(
		built.Record.Model.Parent == plot.Runtime.Monsters,
		"怪兽没有生成在玩家 Plot/Runtime/Monsters"
	)
	expect(
		built.Record.Model:GetAttribute("MonsterOwnerUserId") == player.UserId,
		"怪兽 OwnerUserId 错误"
	)
	local button, pull, buttonReason = PlotButtonAccess.Get(plot, "M1", "M1-S1-Button")
	expect(button ~= nil and pull ~= nil, "玩家 Plot 按钮场景合同缺失：" .. tostring(buttonReason))

	local noUpgradeMoney = MonsterSpawnPointPurchaseCoordinator.Upgrade(player, "M1-S1")
	expect(not noUpgradeMoney.Succeeded, "余额不足时不应允许升级")
	expect(noUpgradeMoney.Reason == "InsufficientMoney", "升级余额拒绝原因错误")
	expect(built.Record.Model.Parent == plot.Runtime.Monsters, "升级拒绝后 P1 不应消失")

	MoneyService.Add(player, upgradeCost)
	expect(
		MonsterSpawnPointActionQuery.GetPrimaryButtonState(player, "M1-S1") == "Ready",
		"余额充足时升级按钮应为 Ready"
	)
	local upgraded = MonsterSpawnPointPurchaseCoordinator.ExecutePrimary(player, "M1-S1")
	expect(upgraded.Succeeded, "升级失败：" .. tostring(upgraded.Reason))
	expect(
		upgraded.Action == "Upgrade" and upgraded.Cost == upgradeCost and upgraded.Balance == 0,
		"升级扣款错误"
	)
	expect(upgraded.Record ~= nil and upgraded.Record.MonsterKey == "P4", "升级后不是 P4")
	expect(upgraded.NextButtonState == "Locked", "最高级出生点按钮应为 Locked")
	local finalActions = assert(MonsterSpawnPointActionQuery.Get(player, "M1-S1"))
	expect(finalActions.Attack.Allowed, "升级后空闲怪兽应该允许进入攻击 UI")

	-- 已拥有的出生点不受后来降低容量影响；显式重载必须从出生点保存状态恢复 P4。
	expect(MonsterRosterCoordinator.SetCapacity(player, 0).Succeeded, "无法降低已有怪兽容量")
	PlayerMonsterRuntimeCoordinator.Unload(player)
	local loaded = PlayerMonsterRuntimeCoordinator.Load(player)
	expect(loaded.Succeeded and loaded.LoadedCount == 1, "重载失败：" .. tostring(loaded.Reason))
	local restored = MonsterRosterCoordinator.Get(player, "M1-S1")
	expect(restored ~= nil and restored.MonsterKey == "P4", "重载没有恢复 P4")
	expect(restored.Model ~= nil and restored.Model.Parent == plot.Runtime.Monsters, "重载模型父级错误")
	return true
end

return PlayerMonsterRuntimeSpec
