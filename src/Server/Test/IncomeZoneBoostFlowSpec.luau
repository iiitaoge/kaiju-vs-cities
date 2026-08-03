--[[
	职责：验证 Plot 产钱区域的一次性 Boost 服务端完整链路。
	输入：一名已完成数据加载且已分配 Plot 的在线 Player。
	输出：Boost 后倍率、生命迁移和两秒自动收入依赖的区域领取结果。
	内部算法：保存快照 → 建造默认已解锁的 R1 → 制造 25% 损伤 → 购买 Boost → 核对倍率/生命/收入 → 恢复。
	不负责：触碰实体按钮、等待自动循环、测试客户端颜色或修改 DataStore。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseHealthStateService = require(script.Parent.Parent.HouseHealthStateService)
local HouseIncomeService = require(script.Parent.Parent.HouseIncomeService)
local HouseStateService = require(script.Parent.Parent.HouseStateService)
local IncomeZoneBoostConfigs = require(script.Parent.Parent.IncomeZoneBoostConfigs)
local IncomeZoneBoostCoordinator = require(script.Parent.Parent.IncomeZoneBoostCoordinator)
local IncomeZonePrimaryCoordinator = require(script.Parent.Parent.IncomeZonePrimaryCoordinator)
local MoneyService = require(script.Parent.Parent.MoneyService)
local PlayerCityRuntimeCoordinator = require(script.Parent.Parent.PlayerCityRuntimeCoordinator)
local PlayerSaveStateAdapter = require(script.Parent.Parent.PlayerSaveStateAdapter)
local RegionStateService = require(script.Parent.Parent.RegionStateService)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local PlayerSaveSchema = require(ReplicatedStorage.Shared.Persistence.PlayerSaveSchema)

local Spec = {}

local REGION_ID = "R1"

local function getFirstHouseId(): string
	for _, definition in HouseCatalog.GetAll() do
		if definition.RegionId == REGION_ID then
			return definition.HouseId
		end
	end
	error("R1 缺少房屋配置")
end

local function expectNear(actual: number, expected: number, message: string)
	assert(math.abs(actual - expected) < 0.0001, string.format(
		"%s：expected %.4f, actual %.4f",
		message,
		expected,
		actual
	))
end

function Spec.Run(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是在线 Player")
	local original = PlayerSaveStateAdapter.Capture(player)
	local houseId = getFirstHouseId()
	local boostConfig = IncomeZoneBoostConfigs[REGION_ID]

	local succeeded, outcome = xpcall(function()
		HouseHealthStateService.Clear(player)
		PlayerSaveStateAdapter.Apply(player, PlayerSaveSchema.Default())
		local reset = PlayerCityRuntimeCoordinator.Load(player)
		assert(reset.Succeeded, "测试城市初始化失败：" .. tostring(reset.Reason))

		local build = IncomeZonePrimaryCoordinator.Execute(player, REGION_ID)
		assert(build.Succeeded and build.Action == "Build", "R1 免费建造失败")

		local health = HouseHealthStateService.ResetFull(player, houseId, 1, 100)
		local damaged = HouseHealthStateService.ApplyDamage(
			player,
			houseId,
			health.Generation,
			25
		)
		assert(damaged.Accepted and damaged.CurrentHealth == 75, "测试损伤创建失败")

		MoneyService.Set(player, boostConfig.Cost)
		local boosted = IncomeZoneBoostCoordinator.Execute(player, REGION_ID)
		assert(boosted.Succeeded, "R1 Boost 失败：" .. tostring(boosted.Reason))
		local region = RegionStateService.Get(player, REGION_ID)
		assert(region.IncomeMultiplier == 2, "Boost 后收入倍率应为 2")
		assert(region.HealthMultiplier == 2, "Boost 后生命倍率应为 2")
		assert(region.BoostPurchased, "BoostPurchased 应为 true")
		assert(region.AutoIncome, "AutoIncome 应为 true")

		local migrated = assert(HouseHealthStateService.Get(player, houseId))
		expectNear(migrated.MaxHealth, 200, "Boost 最大生命")
		expectNear(migrated.CurrentHealth, 150, "Boost 当前生命应保持 75%")
		local model = assert(PlayerCityRuntimeCoordinator.ResolveBuilding(player, houseId))
		expectNear(model:GetAttribute("BuildingMaxHealth"), 200, "Model 最大生命镜像")
		expectNear(model:GetAttribute("BuildingCurrentHealth"), 150, "Model 当前生命镜像")

		local lastIncomeAt = assert(HouseStateService.Get(player, houseId).LastIncomeAt)
		local collection = HouseIncomeService.CollectRegion(player, REGION_ID, lastIncomeAt + 2)
		assert(collection.Accepted, "Boost 后区域领取失败：" .. tostring(collection.Reason))
		expectNear(collection.Generated, 200, "R1 Boost 后两秒区域收入")
		expectNear(collection.Collected, 200, "R1 Boost 后两秒自动领取金额")

		local repeated = IncomeZoneBoostCoordinator.Execute(player, REGION_ID)
		assert(not repeated.Succeeded and repeated.Reason == "AlreadyBoosted", "Boost 必须只能购买一次")

		return {
			IncomeMultiplier = region.IncomeMultiplier,
			HealthMultiplier = region.HealthMultiplier,
			CurrentHealth = migrated.CurrentHealth,
			MaxHealth = migrated.MaxHealth,
			GeneratedInTwoSeconds = collection.Generated,
			RepeatedReason = repeated.Reason,
		}
	end, debug.traceback)

	HouseHealthStateService.Clear(player)
	PlayerSaveStateAdapter.Apply(player, original)
	local restored = PlayerCityRuntimeCoordinator.Load(player)
	assert(restored.Succeeded, "恢复测试前城市失败：" .. tostring(restored.Reason))
	if not succeeded then
		error(outcome)
	end
	return outcome
end

return Spec
