--[[
	职责：在客户端呈现一栋服务器权威房屋的摧毁或重建。
	输入：已通过协议验证的 HouseDestroyed / HouseRebuilding Command。
	输出：无业务返回；表现失败只记录警告。
	内部算法：按 Owner/Zone/House/Level 解析 Slot 与模板，复用拆除或升起动画。
	不负责：不修改服务器状态、不创建持久建筑、不决定何时重建。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingPlacement = require(ReplicatedStorage.Shared.Building.BuildingPlacement)
local BuildingPresentationConfigs = require(
	ReplicatedStorage.Shared.Building.BuildingPresentationConfigs
)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local IncomeBuildingProgressionRules = require(
	ReplicatedStorage.Shared.Building.IncomeBuildingProgressionRules
)
local BuildingTemplateResolver = require(script.Parent.BuildingTemplateResolver)
local LocalBuildingDemolitionAnimation = require(script.Parent.LocalBuildingDemolitionAnimation)
local LocalBuildingRiseAnimation = require(script.Parent.LocalBuildingRiseAnimation)
local LocalBuildingVisibility = require(script.Parent.LocalBuildingVisibility)
local LocalPlayerCityRuntimeAccess = require(script.Parent.LocalPlayerCityRuntimeAccess)

local HouseLifecyclePresentationController = {}

local function resolve(command, config)
	local plot = assert(
		LocalPlayerCityRuntimeAccess.WaitForPlot(command.OwnerUserId, config.ResolveTimeout),
		string.format("找不到玩家 Plot：%d", command.OwnerUserId)
	)
	local definition = assert(HouseCatalog.Get(command.HouseId), "找不到房屋定义：" .. command.HouseId)
	assert(definition.RegionId == command.RegionId, "房屋与表现 Zone 不匹配：" .. command.HouseId)
	local slot = assert(
		LocalPlayerCityRuntimeAccess.FindSlot(plot, command.RegionId, command.HouseId),
		"找不到房屋 Slot：" .. command.HouseId
	)
	local modelLevel = assert(
		IncomeBuildingProgressionRules.ResolveModelLevel(
			command.Level,
			definition.BuildAtRegionLevel,
			definition.RegionLevelsPerModelLevel,
			definition.MaxModelLevel
		),
		"房屋尚未到建造等级：" .. command.HouseId
	)
	local template = assert(
		BuildingTemplateResolver.Resolve(
			definition.ModelRoot,
			definition.GroupName,
			definition.VariantName,
			modelLevel
		),
		"找不到房屋等级模板：" .. command.HouseId
	)
	return plot, slot, template, BuildingPlacement.GetTargetPivot(template, slot.CFrame)
end

local function presentDestroyed(command, config)
	local plot, slot, template, targetPivot = resolve(command, config)
	local authoritativeModel = LocalPlayerCityRuntimeAccess.FindBuilding(plot, command.HouseId)
	if authoritativeModel then
		LocalBuildingVisibility.Hide(authoritativeModel)
	end
	LocalBuildingDemolitionAnimation.Play(
		template,
		targetPivot,
		slot.Position.Y,
		config.Demolish
	)
end

local function presentRebuilding(command, config)
	local plot, slot, template, targetPivot = resolve(command, config)
	local authoritativeModel = assert(
		LocalPlayerCityRuntimeAccess.WaitForBuilding(
			plot,
			command.HouseId,
			config.ResolveTimeout
		),
		"找不到重建后的服务器权威建筑：" .. command.HouseId
	)
	assert(
		authoritativeModel:GetAttribute("BuildingOwnerUserId") == command.OwnerUserId,
		"重建建筑 OwnerUserId 不匹配"
	)
	assert(
		authoritativeModel:GetAttribute("BuildingZoneId") == command.RegionId,
		"重建建筑 ZoneId 不匹配"
	)
	assert(
		authoritativeModel:GetAttribute("BuildingLevel") == command.Level,
		"重建建筑 Level 不匹配"
	)

	local snapshot = LocalBuildingVisibility.Hide(authoritativeModel)
	local succeeded, message = xpcall(function()
		LocalBuildingRiseAnimation.Play(
			template,
			targetPivot,
			slot.Position.Y,
			config.Rise
		)
	end, debug.traceback)
	LocalBuildingVisibility.Restore(snapshot)
	if not succeeded then
		error(message)
	end
end

function HouseLifecyclePresentationController.Present(command)
	local config = BuildingPresentationConfigs[command.PresentationId]
	if not config then
		warn("找不到房屋生命周期表现配置：" .. tostring(command.PresentationId))
		return
	end

	local succeeded, message = xpcall(function()
		if command.Kind == "HouseDestroyed" then
			presentDestroyed(command, config)
		else
			presentRebuilding(command, config)
		end
	end, debug.traceback)
	if not succeeded then
		warn("房屋生命周期表现失败：" .. tostring(message))
	end
end

return HouseLifecyclePresentationController
