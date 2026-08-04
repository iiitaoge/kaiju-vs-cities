--[[
	职责：组装单栋房屋从权威摧毁到自动重建完成的完整服务器链路。

	输入：Destroy 接收在线防守玩家和当前 Alive 的 HouseId。
	输出：是否成功、稳定失败原因、RespawnAt 和被摧毁时等级。
	内部算法：状态摧毁 → 移除单栋 Model → 全员拆除表现 → 监视区域敌方怪兽占用；
		占用解除后重新等待完整时长，再恢复最新等级 Model → Rebuilding → 全员升起表现 → Alive；
		恢复失败保持 Destroyed 并重试，升起期间再次被占用则中止本次重建。

	不负责：不结算收入、不选择攻击目标、不发攻击奖励、不播放客户端动画。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local RuntimeBuildingIdentity = require(
	ReplicatedStorage.Shared.Building.RuntimeBuildingIdentity
)
local CityBuildingPresentationPublisher = require(
	script.Parent.CityBuildingPresentationPublisher
)
local HouseLifecycleConfigs = require(script.Parent.HouseLifecycleConfigs)
local HouseHealthStateService = require(script.Parent.HouseHealthStateService)
local HouseStateService = require(script.Parent.HouseStateService)
local HouseWorldUIPresentationService = require(script.Parent.HouseWorldUIPresentationService)
local PlayerCityRuntimeCoordinator = require(script.Parent.PlayerCityRuntimeCoordinator)
local PlayerRebirthBonusQuery = require(script.Parent.PlayerRebirthBonusQuery)
local PlayerStructureDurabilityResolver = require(
	script.Parent.PlayerStructureDurabilityResolver
)
local WorkspacePlayerRegionMonsterOccupancyQuery = require(
	script.Parent.WorkspacePlayerRegionMonsterOccupancyQuery
)
local ZoneStateService = require(script.Parent.ZoneStateService)

local HouseLifecycleCoordinator = {}

export type DestroyResult = {
	Succeeded: boolean,
	Reason: string?,
	RespawnAt: number?,
	Level: number?,
}

local config = HouseLifecycleConfigs.Default
local presentationConfig = assert(
	BuildingPresentationConfigs[config.PresentationId],
	"找不到房屋生命周期表现配置：" .. config.PresentationId
)
type RebuildSchedule = {
	RespawnAt: number,
	ObservedOccupied: boolean,
}

local scheduledByPlayer: { [Player]: { [string]: RebuildSchedule } } = setmetatable(
	{},
	{ __mode = "k" }
)

local function result(
	succeeded: boolean,
	reason: string?,
	respawnAt: number?,
	level: number?
): DestroyResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		RespawnAt = respawnAt,
		Level = level,
	}
end

local function getScheduled(player: Player, houseId: string): RebuildSchedule?
	local scheduled = scheduledByPlayer[player]
	return scheduled and scheduled[houseId] or nil
end

local function setScheduled(
	player: Player,
	houseId: string,
	respawnAt: number,
	observedOccupied: boolean
): RebuildSchedule
	local scheduled = scheduledByPlayer[player]
	if not scheduled then
		scheduled = {}
		scheduledByPlayer[player] = scheduled
	end
	local schedule = {
		RespawnAt = respawnAt,
		ObservedOccupied = observedOccupied,
	}
	scheduled[houseId] = schedule
	return schedule
end

local function clearScheduled(
	player: Player,
	houseId: string,
	schedule: RebuildSchedule
)
	local scheduled = scheduledByPlayer[player]
	if not scheduled or scheduled[houseId] ~= schedule then
		return
	end
	scheduled[houseId] = nil
	if next(scheduled) == nil then
		scheduledByPlayer[player] = nil
	end
end

local function publish(command)
	local succeeded, message = pcall(CityBuildingPresentationPublisher.Publish, command)
	if not succeeded then
		warn("广播房屋生命周期表现失败：" .. tostring(message))
	end
end

local scheduleRebuild

local function isRegionOccupied(player: Player, houseId: string): boolean
	local definition = HouseCatalog.Get(houseId)
	return definition ~= nil
		and WorkspacePlayerRegionMonsterOccupancyQuery.IsOccupied(
			player,
			definition.RegionId
		)
end

local function finishRebuild(
	player: Player,
	houseId: string,
	model: Model
)
	if player.Parent ~= Players then
		return
	end
	local state = HouseStateService.Get(player, houseId)
	if state.LifeState ~= "Rebuilding" then
		return
	end

	local current = PlayerCityRuntimeCoordinator.ResolveBuilding(player, houseId)
	if isRegionOccupied(player, houseId) then
		if current == model then
			local removal = PlayerCityRuntimeCoordinator.RemoveBuilding(
				player,
				houseId,
				model
			)
			if not removal.Succeeded then
				warn(string.format(
					"区域被怪兽占用时移除重建房屋失败：%s/%s (%s)",
					player.Name,
					houseId,
					removal.Reason or "Unknown"
				))
				task.delay(config.RetryDelaySeconds, function()
					finishRebuild(player, houseId, model)
				end)
				return
			end
		end

		local retryAt = os.time() + config.RebuildDelaySeconds
		local _, aborted = HouseStateService.AbortRebuild(player, houseId, retryAt)
		if aborted then
			scheduleRebuild(player, houseId, retryAt, true)
		end
		return
	end

	if current == model and model.Parent then
		local definition = HouseCatalog.Get(houseId)
		local level = definition and ZoneStateService.GetLevel(player, definition.RegionId)
		local durability = definition and PlayerStructureDurabilityResolver.Resolve(
			player,
			definition.RegionId,
			level
		)
		if not definition or not durability then
			warn(string.format("重建房屋缺少耐久配置：%s/%s", player.Name, houseId))
			return
		end
		local health = HouseHealthStateService.ResetFull(
			player,
			houseId,
			level,
			durability.MaxHealth
		)
		model:SetAttribute("BuildingCurrentHealth", health.CurrentHealth)
		model:SetAttribute("BuildingMaxHealth", health.MaxHealth)
		model:SetAttribute("BuildingHealthGeneration", health.Generation)
		BuildPresentationVisibility.Restore(model)
		local _, completed = HouseStateService.CompleteRebuild(player, houseId, os.time())
		if completed then
			HouseWorldUIPresentationService.Refresh(player, houseId, model)
			return
		end
	end

	local retryAt = os.time() + config.RetryDelaySeconds
	local _, aborted = HouseStateService.AbortRebuild(player, houseId, retryAt)
	if aborted then
		scheduleRebuild(player, houseId, retryAt, false)
	end
end

local monitorRebuild

local function attemptRebuild(
	player: Player,
	houseId: string,
	schedule: RebuildSchedule
)
	if getScheduled(player, houseId) ~= schedule then
		return
	end
	if player.Parent ~= Players then
		clearScheduled(player, houseId, schedule)
		return
	end

	local state = HouseStateService.Get(player, houseId)
	if state.LifeState ~= "Destroyed" or state.RespawnAt ~= schedule.RespawnAt then
		clearScheduled(player, houseId, schedule)
		return
	end

	local restored = PlayerCityRuntimeCoordinator.RestoreBuilding(player, houseId, true)
	if not restored.Succeeded or not restored.Model then
		warn(string.format(
			"房屋自动重建暂时失败，将重试：%s/%s (%s)",
			player.Name,
			houseId,
			restored.Reason or "Unknown"
		))
		task.delay(config.RetryDelaySeconds, function()
			monitorRebuild(player, houseId, schedule)
		end)
		return
	end

	local model = restored.Model
	local _, began = HouseStateService.BeginRebuild(
		player,
		houseId,
		schedule.RespawnAt
	)
	if not began then
		PlayerCityRuntimeCoordinator.RemoveBuilding(player, houseId, model)
		clearScheduled(player, houseId, schedule)
		return
	end
	HouseWorldUIPresentationService.Refresh(player, houseId, model)
	clearScheduled(player, houseId, schedule)

	local definition = assert(HouseCatalog.Get(houseId), "重建房屋定义已消失：" .. houseId)
	local level = ZoneStateService.GetLevel(player, definition.RegionId)
	local buildSpeedMultiplier = PlayerRebirthBonusQuery.Get(player).BuildSpeedMultiplier
	publish({
		Kind = "HouseRebuilding",
		OwnerUserId = player.UserId,
		RegionId = definition.RegionId,
		HouseId = houseId,
		Level = level,
		PresentationId = config.PresentationId,
		BuildSpeedMultiplier = buildSpeedMultiplier,
	})
	task.delay(BuildPresentationTiming.ScaleDuration(
		presentationConfig.Rise.TotalDuration,
		buildSpeedMultiplier
	), function()
		finishRebuild(player, houseId, model)
	end)
end

monitorRebuild = function(
	player: Player,
	houseId: string,
	schedule: RebuildSchedule
)
	if getScheduled(player, houseId) ~= schedule then
		return
	end
	if player.Parent ~= Players then
		clearScheduled(player, houseId, schedule)
		return
	end

	local state = HouseStateService.Get(player, houseId)
	if state.LifeState ~= "Destroyed" or state.RespawnAt ~= schedule.RespawnAt then
		clearScheduled(player, houseId, schedule)
		return
	end

	if isRegionOccupied(player, houseId) then
		schedule.ObservedOccupied = true
		task.delay(config.OccupancyPollIntervalSeconds, function()
			monitorRebuild(player, houseId, schedule)
		end)
		return
	end

	if schedule.ObservedOccupied then
		local respawnAt = os.time() + config.RebuildDelaySeconds
		local _, rescheduled = HouseStateService.RescheduleRebuild(
			player,
			houseId,
			schedule.RespawnAt,
			respawnAt
		)
		if not rescheduled then
			clearScheduled(player, houseId, schedule)
			return
		end
		schedule.RespawnAt = respawnAt
		schedule.ObservedOccupied = false
	end

	local remaining = schedule.RespawnAt - os.time()
	if remaining > 0 then
		task.delay(math.min(config.OccupancyPollIntervalSeconds, remaining), function()
			monitorRebuild(player, houseId, schedule)
		end)
		return
	end
	attemptRebuild(player, houseId, schedule)
end

scheduleRebuild = function(
	player: Player,
	houseId: string,
	respawnAt: number,
	observedOccupied: boolean?
)
	local schedule = setScheduled(
		player,
		houseId,
		respawnAt,
		observedOccupied == true
	)
	task.defer(function()
		monitorRebuild(player, houseId, schedule)
	end)
end

-- 输入：在线防守玩家和当前 Alive 的 HouseId。
-- 输出：摧毁是否提交，以及自动重建的时间和旧建筑等级。
-- 内部算法：先提交状态，再移除预期 Model；移除失败会回滚 Alive。
function HouseLifecycleCoordinator.Destroy(
	player: Player,
	houseId: string
): DestroyResult
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	if player.Parent ~= Players then
		return result(false, "PlayerUnavailable", nil, nil)
	end

	local definition = HouseCatalog.Get(houseId)
	if not definition then
		return result(false, "UnknownHouse", nil, nil)
	end
	if HouseStateService.Get(player, houseId).LifeState ~= "Alive" then
		return result(false, "HouseNotAlive", nil, nil)
	end
	local model = PlayerCityRuntimeCoordinator.ResolveBuilding(player, houseId)
	if not model then
		return result(false, "RuntimeBuildingUnavailable", nil, nil)
	end
	local identity, identityReason = RuntimeBuildingIdentity.Read(model)
	if not identity then
		return result(false, identityReason or "InvalidRuntimeBuildingIdentity", nil, nil)
	end
	if identity.OwnerUserId ~= player.UserId
		or identity.HouseId ~= houseId
		or identity.ZoneId ~= definition.RegionId
	then
		return result(false, "RuntimeBuildingIdentityMismatch", nil, nil)
	end

	local respawnAt = os.time() + config.RebuildDelaySeconds
	local _, destroyed = HouseStateService.Destroy(player, houseId, respawnAt)
	if not destroyed then
		return result(false, "HouseNotAlive", nil, nil)
	end
	local removal = PlayerCityRuntimeCoordinator.RemoveBuilding(player, houseId, model)
	if not removal.Succeeded then
		local _, rolledBack = HouseStateService.RollbackDestroy(player, houseId, os.time())
		if not rolledBack then
			warn(string.format("房屋摧毁移除失败且状态回滚失败：%s/%s", player.Name, houseId))
		elseif model.Parent then
			HouseWorldUIPresentationService.Refresh(player, houseId, model)
		end
		return result(false, removal.Reason or "RuntimeBuildingRemoveFailed", nil, nil)
	end

	publish({
		Kind = "HouseDestroyed",
		OwnerUserId = player.UserId,
		RegionId = definition.RegionId,
		HouseId = houseId,
		Level = identity.Level,
		PresentationId = config.PresentationId,
		BuildSpeedMultiplier = PlayerRebirthBonusQuery.Get(player).BuildSpeedMultiplier,
	})
	scheduleRebuild(player, houseId, respawnAt, false)
	return result(true, nil, respawnAt, identity.Level)
end

return HouseLifecycleCoordinator
