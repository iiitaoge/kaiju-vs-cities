--[[
	职责：验证 R3 主入口从锁定到建造、再到整区升级的服务器完整链路。
	输入：一名已完成数据加载且已分配 Plot 的在线 Player。
	输出：各阶段动作及最终运行时建筑数量；测试结束恢复玩家原始持久状态和城市。
	内部算法：保存快照 → 应用默认档 → 查询/充值/执行三阶段 → 核对 8 栋建筑 → 恢复快照。
	不负责：触碰实体按钮、测试客户端动画或修改 DataStore。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseStateService = require(script.Parent.Parent.HouseStateService)
local IncomeZoneActionQuery = require(script.Parent.Parent.IncomeZoneActionQuery)
local IncomeZonePrimaryCoordinator = require(script.Parent.Parent.IncomeZonePrimaryCoordinator)
local MoneyService = require(script.Parent.Parent.MoneyService)
local PlayerCityRuntimeCoordinator = require(script.Parent.Parent.PlayerCityRuntimeCoordinator)
local PlayerSaveStateAdapter = require(script.Parent.Parent.PlayerSaveStateAdapter)
local RegionEconomyConfigs = require(script.Parent.Parent.RegionEconomyConfigs)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local PlayerSaveSchema = require(ReplicatedStorage.Shared.Persistence.PlayerSaveSchema)

local Spec = {}

local REGION_ID = "R3"

local function assertRuntimeBuildings(player: Player, expectedLevel: number): number
	local count = 0
	for _, definition in HouseCatalog.GetAll() do
		if definition.RegionId ~= REGION_ID then
			continue
		end
		assert(
			HouseStateService.Get(player, definition.HouseId).LifeState == "Alive",
			definition.HouseId .. " 应为 Alive"
		)
		local model = assert(
			PlayerCityRuntimeCoordinator.ResolveBuilding(player, definition.HouseId),
			definition.HouseId .. " 缺少服务器运行时 Model"
		)
		assert(model:GetAttribute("BuildingLevel") == expectedLevel, definition.HouseId .. " 等级错误")
		count += 1
	end
	assert(count == 8, string.format("R3 应有 8 栋运行时建筑，实际为 %d", count))
	return count
end

function Spec.Run(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是在线 Player")
	local original = PlayerSaveStateAdapter.Capture(player)
	local economy = RegionEconomyConfigs[REGION_ID]

	local succeeded, outcome = xpcall(function()
		PlayerSaveStateAdapter.Apply(player, PlayerSaveSchema.Default())
		local reset = PlayerCityRuntimeCoordinator.Load(player)
		assert(reset.Succeeded, "测试城市初始化失败：" .. tostring(reset.Reason))

		local locked = assert(IncomeZoneActionQuery.Get(player, REGION_ID))
		assert(locked.PrimaryAction == "Unlock", "R3 初始动作应为 Unlock")
		assert(locked.PrimaryButtonState == "Insufficient", "余额 0 时应为 Insufficient")

		MoneyService.Set(player, economy.UnlockCost)
		local unlock = IncomeZonePrimaryCoordinator.Execute(player, REGION_ID)
		assert(unlock.Succeeded and unlock.Action == "Unlock", "R3 解锁失败")
		assert(unlock.Snapshot.PrimaryAction == "Build", "解锁后应进入 Build")

		MoneyService.Set(player, economy.PurchaseCost)
		local build = IncomeZonePrimaryCoordinator.Execute(player, REGION_ID)
		assert(build.Succeeded and build.Action == "Build", "R3 建造失败")
		local buildCount = assertRuntimeBuildings(player, 1)

		MoneyService.Set(player, economy.UpgradeBaseCost)
		local upgrade = IncomeZonePrimaryCoordinator.Execute(player, REGION_ID)
		assert(upgrade.Succeeded and upgrade.Action == "Upgrade", "R3 升级失败")
		local upgradeCount = assertRuntimeBuildings(player, 2)

		return {
			UnlockAction = unlock.Action,
			BuildAction = build.Action,
			UpgradeAction = upgrade.Action,
			BuildCount = buildCount,
			UpgradeCount = upgradeCount,
		}
	end, debug.traceback)

	PlayerSaveStateAdapter.Apply(player, original)
	local restored = PlayerCityRuntimeCoordinator.Load(player)
	assert(restored.Succeeded, "恢复测试前城市失败：" .. tostring(restored.Reason))
	if not succeeded then
		error(outcome)
	end
	return outcome
end

return Spec
