--[[
	职责：验证 R3 的前置等级解锁、建造、模型封顶后数值升级和 30 级满级状态。
	输入：一名已完成数据加载且已分配 Plot 的在线 Player。
	输出：各阶段动作及最终运行时建筑数量；测试结束恢复玩家原始持久状态和城市。
	内部算法：保存快照 → 应用默认档 → 查询/充值/执行四阶段 → 核对 8 栋建筑和满级状态 → 恢复快照。
	不负责：触碰实体按钮、测试客户端动画或修改 DataStore。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseStateService = require(script.Parent.Parent.HouseStateService)
local EconomyMath = require(script.Parent.Parent.EconomyMath)
local IncomeZoneActionQuery = require(script.Parent.Parent.IncomeZoneActionQuery)
local IncomeZonePrimaryCoordinator = require(script.Parent.Parent.IncomeZonePrimaryCoordinator)
local IncomeZoneUnlockCoordinator = require(script.Parent.Parent.IncomeZoneUnlockCoordinator)
local MoneyService = require(script.Parent.Parent.MoneyService)
local PlayerCityRuntimeCoordinator = require(script.Parent.Parent.PlayerCityRuntimeCoordinator)
local PlayerSaveStateAdapter = require(script.Parent.Parent.PlayerSaveStateAdapter)
local PlayerZoneSceneVisibilityService = require(
	script.Parent.Parent.PlayerZoneSceneVisibilityService
)
local RegionEconomyConfigs = require(script.Parent.Parent.RegionEconomyConfigs)
local RegionStateService = require(script.Parent.Parent.RegionStateService)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local PlayerSaveSchema = require(ReplicatedStorage.Shared.Persistence.PlayerSaveSchema)

local Spec = {}

local REGION_ID = "R3"
local NEXT_REGION_ID = "R4"

local function assertNoRuntimeBuildings(player: Player)
	for _, definition in HouseCatalog.GetAll() do
		if definition.RegionId ~= REGION_ID then
			continue
		end
		assert(
			HouseStateService.Get(player, definition.HouseId).LifeState == "Unbuilt",
			definition.HouseId .. " 解锁后不应被建造"
		)
		assert(
			PlayerCityRuntimeCoordinator.ResolveBuilding(player, definition.HouseId) == nil,
			definition.HouseId .. " 解锁后不应有运行时 Model"
		)
	end
end

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
		PlayerZoneSceneVisibilityService.Apply(player, REGION_ID)

		local locked = assert(IncomeZoneActionQuery.Get(player, REGION_ID))
		assert(
			locked.UnlockPrerequisiteZoneId == "R2"
				and locked.UnlockPrerequisiteLevel == 5
				and not locked.UnlockPrerequisiteMet,
			"R3 应等待 R2 Level 5"
		)
		assert(locked.ConstructionAction == "Build", "R3 建造入口语义应为 Build")
		assert(locked.ConstructionButtonState == "Locked", "锁定区域建造按钮应为 Locked")
		assert(locked.UnlockButtonState == "Locked", "前置等级不足时解锁按钮应为 Locked")
		local lockedBuild = IncomeZonePrimaryCoordinator.Execute(player, REGION_ID)
		assert(
			not lockedBuild.Succeeded and lockedBuild.Reason == "RegionLocked",
			"建造入口不得代替 Unlock 解锁区域"
		)

		RegionStateService.SetLevel(player, "R2", 5)
		local available = assert(IncomeZoneActionQuery.Get(player, REGION_ID))
		assert(available.UnlockPrerequisiteMet, "R2 Level 5 后没有开放 R3")
		assert(available.UnlockButtonState == "Insufficient", "R3 余额不足状态错误")

		local blockedNext = assert(IncomeZoneActionQuery.Get(player, NEXT_REGION_ID))
		assert(
			blockedNext.UnlockPrerequisiteZoneId == REGION_ID
				and not blockedNext.UnlockPrerequisiteMet,
			"R4 应等待 R3 Level 5"
		)
		assert(
			not blockedNext.Unlock.Allowed
				and blockedNext.Unlock.Reason == "PrerequisiteZoneLocked",
			"R4 前置未满足时不得解锁"
		)
		local blockedNextUnlock = IncomeZoneUnlockCoordinator.Execute(
			player,
			NEXT_REGION_ID
		)
		assert(
			not blockedNextUnlock.Succeeded
				and blockedNextUnlock.Reason == "PrerequisiteZoneLocked",
			"服务器不得允许越级解锁 R4"
		)

		MoneyService.Set(player, economy.UnlockCost)
		local unlock = IncomeZoneUnlockCoordinator.Execute(player, REGION_ID)
		assert(unlock.Succeeded and unlock.Action == "Unlock", "R3 解锁失败")
		assert(unlock.Snapshot.Level == 0, "解锁不得改变区域等级")
		assert(unlock.Snapshot.ConstructionAction == "Build", "解锁后应进入 Build")
		assertNoRuntimeBuildings(player)
		local stillBlockedNext = assert(IncomeZoneActionQuery.Get(player, NEXT_REGION_ID))
		assert(
			not stillBlockedNext.UnlockPrerequisiteMet
				and stillBlockedNext.Unlock.Reason == "PrerequisiteZoneLevelTooLow",
			"R3 仅解锁时不应提前开放 R4"
		)

		MoneyService.Set(player, economy.PurchaseCost)
		local build = IncomeZonePrimaryCoordinator.Execute(player, REGION_ID)
		assert(build.Succeeded and build.Action == "Build", "R3 建造失败")
		local buildCount = assertRuntimeBuildings(player, 1)

		local upgrade = nil
		local upgradeCount = 0
		local levelThreeModel = nil
		local availableNext = nil
		for targetLevel = 2, 30 do
			MoneyService.Set(player, EconomyMath.GetUpgradeCost(economy, targetLevel - 1))
			upgrade = IncomeZonePrimaryCoordinator.Execute(player, REGION_ID)
			assert(
				upgrade.Succeeded and upgrade.Action == "Upgrade",
				string.format("R3 升级到 Level %d 失败", targetLevel)
			)
			assertRuntimeBuildings(player, targetLevel)
			if targetLevel == 2 then
				upgradeCount = 8
			elseif targetLevel == 3 then
				levelThreeModel = assert(PlayerCityRuntimeCoordinator.ResolveBuilding(player, "R3-H1"))
			elseif targetLevel == 4 then
				assert(
					PlayerCityRuntimeCoordinator.ResolveBuilding(player, "R3-H1") == levelThreeModel,
					"模型封顶后的数值升级不应替换运行时 Model"
				)
			elseif targetLevel == 5 then
				availableNext = assert(IncomeZoneActionQuery.Get(player, NEXT_REGION_ID))
				assert(availableNext.UnlockPrerequisiteMet, "R3 Level 5 后没有开放 R4")
			end
		end
		local maxUpgrade = assert(upgrade)
		local maxCount = assertRuntimeBuildings(player, 30)
		assert(maxUpgrade.NextButtonState == "Special", "满级升级按钮应为 Special")

		return {
			UnlockAction = unlock.Action,
			NextUnlockState = assert(availableNext).UnlockButtonState,
			BuildAction = build.Action,
			UpgradeAction = upgrade.Action,
			BuildCount = buildCount,
			UpgradeCount = upgradeCount,
			MaxCount = maxCount,
			MaxButtonState = maxUpgrade.NextButtonState,
		}
	end, debug.traceback)

	PlayerSaveStateAdapter.Apply(player, original)
	local restored = PlayerCityRuntimeCoordinator.Load(player)
	assert(restored.Succeeded, "恢复测试前城市失败：" .. tostring(restored.Reason))
	PlayerZoneSceneVisibilityService.Apply(player, REGION_ID)
	if not succeeded then
		error(outcome)
	end
	return outcome
end

return Spec
