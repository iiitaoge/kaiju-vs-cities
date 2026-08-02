--[[
	职责：
	- 接收服务器已提交的城市建筑表现命令。

	输入：
	- CityBuildingPresentation RemoteEvent 的 RegionUpgrade 或 HouseLifecycle Command。

	输出：
	- RegionUpgrade 在本模块完成并行拆除与升起；单栋生命周期命令转交对应协调器。

	内部算法：
	- 先由纯协议校验并按 Kind 路由；区域升级按 OwnerUserId 找 Plot 和建筑。
	- 本地隐藏权威建筑，执行两个串行阶段，每阶段内所有房屋并行。
	- 无论动画是否报错都销毁临时表现并恢复权威建筑可见性。

	不负责：
	- 不修改 Zone/House 状态，不创建持久建筑，不发送升级请求。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingPresentationConfigs = require(
	ReplicatedStorage.Shared.Building.BuildingPresentationConfigs
)
local BuildingPlacement = require(ReplicatedStorage.Shared.Building.BuildingPlacement)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local CityBuildingPresentationProtocol = require(
	ReplicatedStorage.Shared.Building.CityBuildingPresentationProtocol
)
local BuildingTemplateResolver = require(script.Parent.BuildingTemplateResolver)
local HouseLifecyclePresentationController = require(
	script.Parent.HouseLifecyclePresentationController
)
local LocalBuildingDemolitionAnimation = require(script.Parent.LocalBuildingDemolitionAnimation)
local LocalBuildingRiseAnimation = require(script.Parent.LocalBuildingRiseAnimation)
local LocalBuildingVisibility = require(script.Parent.LocalBuildingVisibility)
local LocalPlayerCityRuntimeAccess = require(script.Parent.LocalPlayerCityRuntimeAccess)

local CityBuildingPresentationController = {}

type Item = {
	HouseId: string,
	AuthoritativeModel: Model,
	OldTemplate: Model?,
	OldTargetPivot: CFrame?,
	NewTemplate: Model,
	NewTargetPivot: CFrame,
	GroundY: number,
}

local started = false

local function resolveItems(command, config): { Item }
	local plot = LocalPlayerCityRuntimeAccess.WaitForPlot(
		command.OwnerUserId,
		config.ResolveTimeout
	)
	assert(plot, string.format("找不到玩家 Plot：%d", command.OwnerUserId))

	local items = {}
	local seen = {}
	for _, houseId in command.HouseIds do
		assert(not seen[houseId], "表现命令包含重复 HouseId：" .. houseId)
		seen[houseId] = true

		local definition = assert(HouseCatalog.Get(houseId), "找不到房屋定义：" .. houseId)
		assert(definition.RegionId == command.RegionId, "房屋与表现 Region 不匹配：" .. houseId)
		local slot = assert(
			LocalPlayerCityRuntimeAccess.FindSlot(plot, command.RegionId, houseId),
			"找不到房屋 Slot：" .. houseId
		)
		local authoritativeModel = assert(
			LocalPlayerCityRuntimeAccess.WaitForBuilding(plot, houseId, config.ResolveTimeout),
			"找不到服务器权威建筑：" .. houseId
		)
		assert(
			authoritativeModel:GetAttribute("BuildingOwnerUserId") == command.OwnerUserId,
			"服务器建筑 OwnerUserId 不匹配：" .. houseId
		)
		assert(
			authoritativeModel:GetAttribute("BuildingZoneId") == command.RegionId,
			"服务器建筑 RegionId 不匹配：" .. houseId
		)

		local newTemplate = assert(
			BuildingTemplateResolver.Resolve(
				definition.ModelRoot,
				definition.GroupName,
				definition.VariantName,
				command.NewLevel
			),
			"找不到新等级模板：" .. houseId
		)
		local oldTemplate = if command.PreviousLevel > 0
			then BuildingTemplateResolver.Resolve(
				definition.ModelRoot,
				definition.GroupName,
				definition.VariantName,
				command.PreviousLevel
			)
			else nil
		if command.PreviousLevel > 0 then
			assert(oldTemplate, "找不到旧等级模板：" .. houseId)
		end

		table.insert(items, {
			HouseId = houseId,
			AuthoritativeModel = authoritativeModel,
			OldTemplate = oldTemplate,
			OldTargetPivot = if oldTemplate
				then BuildingPlacement.GetTargetPivot(oldTemplate, slot.CFrame)
				else nil,
			NewTemplate = newTemplate,
			NewTargetPivot = BuildingPlacement.GetTargetPivot(newTemplate, slot.CFrame),
			GroundY = slot.Position.Y,
		})
	end
	return items
end

local function runParallel(items: { Item }, callback): { string }
	local remaining = #items
	local errors = {}
	for _, item in items do
		task.spawn(function()
			local succeeded, message = xpcall(function()
				callback(item)
			end, debug.traceback)
			if not succeeded then
				table.insert(errors, string.format("%s: %s", item.HouseId, tostring(message)))
			end
			remaining -= 1
		end)
	end
	while remaining > 0 do
		task.wait()
	end
	return errors
end

local function presentRegionUpgrade(command)
	local config = BuildingPresentationConfigs[command.PresentationId]
	if not config then
		warn("找不到建筑表现配置：" .. command.PresentationId)
		return
	end

	local snapshots = {}
	local succeeded, message = xpcall(function()
		local items = resolveItems(command, config)
		for _, item in items do
			snapshots[item.AuthoritativeModel] = LocalBuildingVisibility.Hide(
				item.AuthoritativeModel
			)
		end

		if command.PreviousLevel > 0 then
			local demolishErrors = runParallel(items, function(item)
				LocalBuildingDemolitionAnimation.Play(
					item.OldTemplate :: Model,
					item.OldTargetPivot :: CFrame,
					item.GroundY,
					config.Demolish
				)
			end)
			if #demolishErrors > 0 then
				warn("区域拆除表现部分失败：\n" .. table.concat(demolishErrors, "\n"))
			end
		end

		local riseErrors = runParallel(items, function(item)
			LocalBuildingRiseAnimation.Play(
				item.NewTemplate,
				item.NewTargetPivot,
				item.GroundY,
				config.Rise
			)
		end)
		if #riseErrors > 0 then
			warn("区域升起表现部分失败：\n" .. table.concat(riseErrors, "\n"))
		end
	end, debug.traceback)

	for _, snapshot in snapshots do
		LocalBuildingVisibility.Restore(snapshot)
	end
	if not succeeded then
		warn("城市建筑表现失败：" .. tostring(message))
	end
end

function CityBuildingPresentationController.Start()
	if started then
		return
	end
	started = true

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild("CityBuildingPresentation")
	assert(remote:IsA("RemoteEvent"), "CityBuildingPresentation 必须是 RemoteEvent")
	remote.OnClientEvent:Connect(function(command)
		local valid, reason = CityBuildingPresentationProtocol.Validate(command)
		if not valid then
			warn("拒绝城市建筑表现命令：" .. (reason or "Unknown"))
			return
		end
		if command.Kind == "RegionUpgrade" then
			task.spawn(presentRegionUpgrade, command)
		else
			task.spawn(HouseLifecyclePresentationController.Present, command)
		end
	end)
end

return CityBuildingPresentationController
