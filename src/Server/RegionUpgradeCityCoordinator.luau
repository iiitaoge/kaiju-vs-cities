--[[
	职责：组装一次服务器权威的区域升级、建筑刷新和全员表现广播。

	输入：Player、RegionId。
	输出：供 ButtonService 使用的 clientAction(nil) 和按钮下一状态。

	内部算法：
	1. 调用 RegionUpgradeService 提交升级事务。
	2. 让 RegionAutoUnlockCoordinator 处理达到门槛的配置型自动解锁。
	3. 只有房屋首次出现或模型等级变化时才刷新 Zone 并广播表现。
	4. 模型已经封顶时只更新等级、HP 和世界 UI 数值，不重复拆建模型。

	不负责：不计算升级价格、不 Clone 客户端表现、不解析场景 Slot。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutomaticIncomeRatePresentationService = require(
	script.Parent.AutomaticIncomeRatePresentationService
)
local BuildingPresentationConfigs = require(
	ReplicatedStorage.Shared.Building.BuildingPresentationConfigs
)
local BuildPresentationVisibility = require(
	ReplicatedStorage.Shared.Building.BuildPresentationVisibility
)
local BuildPresentationTiming = require(
	ReplicatedStorage.Shared.Building.BuildPresentationTiming
)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local CityBuildingPresentationPublisher = require(script.Parent.CityBuildingPresentationPublisher)
local HouseHealthStateService = require(script.Parent.HouseHealthStateService)
local HouseWorldUIPresentationService = require(script.Parent.HouseWorldUIPresentationService)
local PlayerCityRuntimeCoordinator = require(script.Parent.PlayerCityRuntimeCoordinator)
local PlayerRebirthBonusQuery = require(script.Parent.PlayerRebirthBonusQuery)
local PlayerZoneSceneVisibilityService = require(script.Parent.PlayerZoneSceneVisibilityService)
local PlayerStructureDurabilityResolver = require(
	script.Parent.PlayerStructureDurabilityResolver
)
local RegionAutoUnlockCoordinator = require(script.Parent.RegionAutoUnlockCoordinator)
local RegionUpgradeService = require(script.Parent.RegionUpgradeService)
local IncomeBuildingProgressionRules = require(
	ReplicatedStorage.Shared.Building.IncomeBuildingProgressionRules
)

local RegionUpgradeCityCoordinator = {}

local function hasPresentationChange(regionId: string, previousLevel: number, newLevel: number): boolean
	for _, definition in HouseCatalog.GetAll() do
		if definition.RegionId ~= regionId then
			continue
		end
		local previousModelLevel = IncomeBuildingProgressionRules.ResolveModelLevel(
			previousLevel,
			definition.BuildAtRegionLevel,
			definition.RegionLevelsPerModelLevel,
			definition.MaxModelLevel
		)
		local newModelLevel = IncomeBuildingProgressionRules.ResolveModelLevel(
			newLevel,
			definition.BuildAtRegionLevel,
			definition.RegionLevelsPerModelLevel,
			definition.MaxModelLevel
		)
		if previousModelLevel ~= newModelLevel then
			return true
		end
	end
	return false
end

local function listRegionHouseIds(player: Player, regionId: string): { string }
	local houseIds = {}
	for houseId, model in PlayerCityRuntimeCoordinator.ListBuildings(player) do
		if model:GetAttribute("BuildingZoneId") == regionId then
			table.insert(houseIds, houseId)
		end
	end
	table.sort(houseIds)
	return houseIds
end

local function refreshNumericState(
	player: Player,
	regionId: string,
	newLevel: number,
	maxHealth: number
)
	for houseId, model in PlayerCityRuntimeCoordinator.ListBuildings(player) do
		if model:GetAttribute("BuildingZoneId") ~= regionId then
			continue
		end
		model:SetAttribute("BuildingLevel", newLevel)
		local health = HouseHealthStateService.Ensure(player, houseId, newLevel, maxHealth)
		model:SetAttribute("BuildingCurrentHealth", health.CurrentHealth)
		model:SetAttribute("BuildingMaxHealth", health.MaxHealth)
		model:SetAttribute("BuildingHealthGeneration", health.Generation)
		local refreshed, refreshReason = HouseWorldUIPresentationService.Refresh(
			player,
			houseId,
			model
		)
		if not refreshed then
			warn(string.format(
				"区域数值升级后刷新房屋 UI 失败：%s/%s (%s)",
				player.Name,
				houseId,
				refreshReason or "Unknown"
			))
		end
	end
end

function RegionUpgradeCityCoordinator.Upgrade(player: Player, regionId: string)
	local upgrade = RegionUpgradeService.Upgrade(player, regionId)
	if not upgrade.Succeeded then
		return nil, upgrade.NextButtonState
	end
	AutomaticIncomeRatePresentationService.Refresh(player)

	local newLevel = assert(upgrade.NewLevel, "成功升级必须返回 NewLevel")
	local presentationId = assert(
		upgrade.PresentationId,
		"成功升级必须配置 PresentationId"
	)
	local presentation = assert(
		BuildingPresentationConfigs[presentationId],
		"找不到建筑表现配置：" .. presentationId
	)
	local durability, durabilityReason = PlayerStructureDurabilityResolver.Resolve(
		player,
		regionId,
		newLevel
	)
	assert(
		durability,
		string.format(
			"区域升级缺少有效耐久：%s/%s (%s)",
			regionId,
			tostring(newLevel),
			durabilityReason or "Unknown"
		)
	)
	local maxHealth = durability.MaxHealth
	local buildSpeedMultiplier = PlayerRebirthBonusQuery.Get(player).BuildSpeedMultiplier
	local presentationChanged = hasPresentationChange(
		regionId,
		upgrade.PreviousLevel,
		newLevel
	)
	RegionAutoUnlockCoordinator.UnlockEligibleDependents(player, regionId, newLevel)

	-- 在替换运行时 Model 前迁移已有会话血量，保证受伤建筑升级时保持原比例。
	for _, definition in HouseCatalog.GetAll() do
		if definition.RegionId == regionId
			and HouseHealthStateService.Get(player, definition.HouseId) then
			HouseHealthStateService.Ensure(
				player,
				definition.HouseId,
				newLevel,
				maxHealth
			)
		end
	end

	local visibility = PlayerZoneSceneVisibilityService.ApplyAll(player)
	if not visibility.Succeeded then
		warn(string.format(
			"区域升级后刷新解锁按钮链失败：%s/%s (%s)",
			player.Name,
			regionId,
			visibility.Reason or "Unknown"
		))
	end

	if not presentationChanged then
		refreshNumericState(player, regionId, newLevel, maxHealth)
		return nil, upgrade.NextButtonState
	end

	local refresh = PlayerCityRuntimeCoordinator.RefreshZone(player, regionId, true)
	if not refresh.Succeeded then
		warn(string.format(
			"区域升级已提交，但服务器建筑刷新失败：%s/%s (%s)",
			player.Name,
			regionId,
			refresh.Reason or "Unknown"
		))
		return nil, upgrade.NextButtonState
	end

	-- RefreshZone 会替换 Model；把服务器会话血量镜像到新实例供所有客户端观察。
	for houseId, model in PlayerCityRuntimeCoordinator.ListBuildings(player) do
		if model:GetAttribute("BuildingZoneId") == regionId then
			local health = HouseHealthStateService.Ensure(
				player,
				houseId,
				newLevel,
				maxHealth
			)
			model:SetAttribute("BuildingCurrentHealth", health.CurrentHealth)
			model:SetAttribute("BuildingMaxHealth", health.MaxHealth)
			model:SetAttribute("BuildingHealthGeneration", health.Generation)
		end
	end

	local houseIds = listRegionHouseIds(player, regionId)
	local presentationModels = {}
	for _, houseId in houseIds do
		local model = PlayerCityRuntimeCoordinator.ResolveBuilding(player, houseId)
		if model then
			table.insert(presentationModels, model)
		end
	end
	local published, publishError = pcall(CityBuildingPresentationPublisher.Publish, {
		Kind = "RegionUpgrade",
		OwnerUserId = player.UserId,
		RegionId = regionId,
		PreviousLevel = upgrade.PreviousLevel,
		NewLevel = newLevel,
		PresentationId = presentationId,
		BuildSpeedMultiplier = buildSpeedMultiplier,
		HouseIds = houseIds,
	})
	if not published then
		for _, model in presentationModels do
			BuildPresentationVisibility.Restore(model)
		end
		warn("区域建筑表现广播失败：" .. tostring(publishError))
		return nil, upgrade.NextButtonState
	end

	local totalDuration = BuildPresentationTiming.ScaleDuration(
		presentation.Rise.TotalDuration,
		buildSpeedMultiplier
	)
	if upgrade.PreviousLevel > 0 then
		totalDuration += BuildPresentationTiming.ScaleDuration(
			presentation.Demolish.TotalDuration,
			buildSpeedMultiplier
		)
	end
	task.wait(totalDuration)
	for _, model in presentationModels do
		BuildPresentationVisibility.Restore(model)
	end
	return nil, upgrade.NextButtonState
end

return RegionUpgradeCityCoordinator
