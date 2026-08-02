--[[
	职责：组装一次服务器权威的区域升级、建筑刷新和全员表现广播。

	输入：Player、RegionId。
	输出：供 ButtonService 使用的 clientAction(nil) 和按钮下一状态。

	内部算法：
	1. 调用 RegionUpgradeService 提交升级事务。
	2. 成功后只刷新该玩家 Plot 中目标 Zone 的权威建筑。
	3. 从运行时索引提取该 Zone 的 HouseIds，向所有客户端发布表现命令。
	4. 等待配置声明的表现时长，使发起玩家的按钮在动画期间保持忙碌。

	不负责：不计算升级价格、不 Clone 客户端表现、不解析场景 Slot。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingPresentationConfigs = require(
	ReplicatedStorage.Shared.Building.BuildingPresentationConfigs
)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local StructureDurabilityConfigs = require(
	ReplicatedStorage.Shared.Building.StructureDurabilityConfigs
)
local CityBuildingPresentationPublisher = require(script.Parent.CityBuildingPresentationPublisher)
local HouseHealthStateService = require(script.Parent.HouseHealthStateService)
local PlayerCityRuntimeCoordinator = require(script.Parent.PlayerCityRuntimeCoordinator)
local RegionUpgradeService = require(script.Parent.RegionUpgradeService)

local RegionUpgradeCityCoordinator = {}

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

function RegionUpgradeCityCoordinator.Upgrade(player: Player, regionId: string)
	local upgrade = RegionUpgradeService.Upgrade(player, regionId)
	if not upgrade.Succeeded then
		return nil, upgrade.NextButtonState
	end

	local newLevel = assert(upgrade.NewLevel, "成功升级必须返回 NewLevel")
	local presentationId = assert(
		upgrade.PresentationId,
		"成功升级必须配置 PresentationId"
	)
	local presentation = assert(
		BuildingPresentationConfigs[presentationId],
		"找不到建筑表现配置：" .. presentationId
	)
	local maxHealth = assert(
		StructureDurabilityConfigs.GetMaxHealth(regionId, newLevel),
		string.format("区域升级缺少耐久配置：%s/%s", regionId, tostring(newLevel))
	)

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

	local refresh = PlayerCityRuntimeCoordinator.RefreshZone(player, regionId)
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
	CityBuildingPresentationPublisher.Publish({
		Kind = "RegionUpgrade",
		OwnerUserId = player.UserId,
		RegionId = regionId,
		PreviousLevel = upgrade.PreviousLevel,
		NewLevel = newLevel,
		PresentationId = presentationId,
		HouseIds = houseIds,
	})

	local totalDuration = presentation.Rise.TotalDuration
	if upgrade.PreviousLevel > 0 then
		totalDuration += presentation.Demolish.TotalDuration
	end
	task.wait(totalDuration)
	return nil, upgrade.NextButtonState
end

return RegionUpgradeCityCoordinator
