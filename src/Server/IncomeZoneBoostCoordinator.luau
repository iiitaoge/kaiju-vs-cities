--[[
	职责：提交一次产钱区域 Boost 购买事务。
	输入：Player、RegionId。
	输出：Succeeded、Reason、最新 Snapshot 和 NextButtonState。
	内部算法：区域加锁 → 旧倍率结算 → 扣款 → 写倍率/自动收入 → 迁移生命 → 领取存量收入。
	不负责：实体按钮、价格配置、收入公式、客户端动画或 DataStore。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseHealthStateService = require(script.Parent.HouseHealthStateService)
local HouseIncomeService = require(script.Parent.HouseIncomeService)
local IncomeZoneBoostQuery = require(script.Parent.IncomeZoneBoostQuery)
local MoneyService = require(script.Parent.MoneyService)
local PlayerCityRuntimeCoordinator = require(script.Parent.PlayerCityRuntimeCoordinator)
local PlayerRegionTransactionLock = require(script.Parent.PlayerRegionTransactionLock)
local PlayerStructureDurabilityResolver = require(
	script.Parent.PlayerStructureDurabilityResolver
)
local RegionStateService = require(script.Parent.RegionStateService)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)

local IncomeZoneBoostCoordinator = {}

local function result(succeeded: boolean, reason: string?, snapshot)
	return {
		Succeeded = succeeded,
		Reason = reason,
		Snapshot = snapshot,
		NextButtonState = if snapshot then snapshot.BoostButtonState else "Locked",
	}
end

local function writeHealthAttributes(model: Model, health)
	model:SetAttribute("BuildingCurrentHealth", health.CurrentHealth)
	model:SetAttribute("BuildingMaxHealth", health.MaxHealth)
	model:SetAttribute("BuildingHealthGeneration", health.Generation)
end

local function migrateRegionHealth(player: Player, regionId: string, level: number)
	local durability, reason = PlayerStructureDurabilityResolver.Resolve(
		player,
		regionId,
		level
	)
	if not durability then
		return false, reason or "DurabilityUnavailable"
	end
	for _, definition in HouseCatalog.GetAll() do
		if definition.RegionId ~= regionId then
			continue
		end
		local model = PlayerCityRuntimeCoordinator.ResolveBuilding(player, definition.HouseId)
		local existing = HouseHealthStateService.Get(player, definition.HouseId)
		if model or existing then
			local health = HouseHealthStateService.Ensure(
				player,
				definition.HouseId,
				level,
				durability.MaxHealth
			)
			if model then
				writeHealthAttributes(model, health)
			end
		end
	end
	return true, nil
end

local function executeUnlocked(player: Player, regionId: string)
	local before = IncomeZoneBoostQuery.Get(player, regionId)
	if not before then
		return result(false, "UnknownIncomeZone", nil)
	end
	local permission = before.Permission
	if not permission.Allowed then
		return result(false, permission.Reason or "BoostLocked", before)
	end
	if not permission.Affordable then
		return result(false, "InsufficientMoney", before)
	end

	local now = os.time()
	local settlement = HouseIncomeService.SettleRegionHouses(player, regionId, now)
	if not settlement.Accepted then
		return result(false, settlement.Reason or "SettlementRejected", before)
	end
	local spend = MoneyService.TrySpend(player, permission.Cost)
	if not spend.Succeeded then
		return result(false, spend.Reason or "InsufficientMoney", IncomeZoneBoostQuery.Get(player, regionId))
	end

	RegionStateService.SetIncomeMultiplier(
		player,
		regionId,
		permission.TargetIncomeMultiplier
	)
	RegionStateService.SetHealthMultiplier(
		player,
		regionId,
		permission.TargetHealthMultiplier
	)
	RegionStateService.SetAutoIncome(player, regionId, permission.TargetAutoIncome)
	RegionStateService.SetBoostPurchased(player, regionId, true)

	local migrated, migrateReason = migrateRegionHealth(player, regionId, before.Level)
	if not migrated then
		warn(string.format(
			"区域 Boost 已提交但生命迁移失败：%s/%s (%s)",
			player.Name,
			regionId,
			migrateReason or "Unknown"
		))
	end
	local collection = HouseIncomeService.CollectRegion(player, regionId, now)
	if not collection.Accepted then
		warn(string.format(
			"区域 Boost 已提交但存量收入领取失败：%s/%s (%s)",
			player.Name,
			regionId,
			collection.Reason or "Unknown"
		))
	end

	local after = IncomeZoneBoostQuery.Get(player, regionId)
	local committed = after ~= nil
		and after.BoostPurchased
		and after.IncomeMultiplier == permission.TargetIncomeMultiplier
		and after.HealthMultiplier == permission.TargetHealthMultiplier
		and after.AutoIncome == permission.TargetAutoIncome
	return result(
		committed,
		if committed then nil else "BoostNotCommitted",
		after
	)
end

function IncomeZoneBoostCoordinator.Execute(player: Player, regionId: string)
	local release = PlayerRegionTransactionLock.TryAcquire(player, regionId)
	if not release then
		local busy = result(false, "ActionBusy", IncomeZoneBoostQuery.Get(player, regionId))
		busy.NextButtonState = "Processing"
		return busy
	end
	local succeeded, outcome = xpcall(function()
		return executeUnlocked(player, regionId)
	end, debug.traceback)
	release()
	if not succeeded then
		warn(string.format("区域 Boost 异常：%s/%s (%s)", player.Name, regionId, tostring(outcome)))
		return result(false, "BoostTransactionError", IncomeZoneBoostQuery.Get(player, regionId))
	end
	return outcome
end

return IncomeZoneBoostCoordinator
