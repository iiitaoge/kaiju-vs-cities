--[[
	职责：为实体按钮和未来 UI 生成产钱区域的权威操作快照。
	输入：Player、RegionId。
	输出：区域状态、余额、Unlock/Build/Upgrade 权限，以及独立的 Unlock/建造按钮状态。
	内部算法：读取当前解锁/前置/等级 → 计算下一动作与价格 → 比较余额。
	不负责：扣款、修改状态、生成建筑、播放表现或 Remote。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyMath = require(script.Parent.EconomyMath)
local MoneyService = require(script.Parent.MoneyService)
local RegionEconomyConfigs = require(script.Parent.RegionEconomyConfigs)
local RegionStateService = require(script.Parent.RegionStateService)
local RegionUpgradeConfigs = require(script.Parent.RegionUpgradeConfigs)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local IncomeZoneActionQuery = {}

local function status(allowed: boolean, reason: string?, cost: number, balance: number, targetLevel: number?)
	return {
		Allowed = allowed,
		Reason = reason,
		Cost = cost,
		Affordable = allowed and balance >= cost,
		TargetLevel = targetLevel,
	}
end

local function buttonState(actionStatus): string
	if actionStatus.Reason == "MaxLevel" then
		return "Special"
	end
	if not actionStatus.Allowed then
		return "Locked"
	end
	return if actionStatus.Affordable then "Ready" else "Insufficient"
end

function IncomeZoneActionQuery.Get(player: Player, regionId: string)
	local zone = ZoneCatalog.Get(regionId)
	local economy = RegionEconomyConfigs[regionId]
	local upgrade = RegionUpgradeConfigs[regionId]
	if not zone or zone.Kind ~= "Income" or not economy or not upgrade then
		return nil
	end

	local balance = MoneyService.Get(player)
	local unlocked = RegionStateService.GetUnlocked(player, regionId)
	local prerequisiteZoneId = zone.UnlockPrerequisiteZoneId
	local prerequisiteLevel = zone.UnlockPrerequisiteLevel
	local prerequisiteUnlocked = prerequisiteZoneId == nil
		or RegionStateService.GetUnlocked(player, prerequisiteZoneId)
	local prerequisiteCurrentLevel = if prerequisiteZoneId
		then RegionStateService.GetLevel(player, prerequisiteZoneId)
		else 0
	local prerequisiteMet = prerequisiteUnlocked
		and (prerequisiteLevel == nil or prerequisiteCurrentLevel >= prerequisiteLevel)
	local level = RegionStateService.GetLevel(player, regionId)
	local nextLevel = level + 1
	local hasNextLevel = upgrade.Levels[nextLevel] ~= nil
	local buildCost = EconomyMath.GetUpgradeCost(economy, 0)
	local upgradeCost = if level >= 1 and hasNextLevel
		then EconomyMath.GetUpgradeCost(economy, level)
		else 0

	local unlockStatus = status(
		not unlocked and prerequisiteMet,
		if unlocked then "AlreadyUnlocked"
		elseif not prerequisiteUnlocked then "PrerequisiteZoneLocked"
		elseif not prerequisiteMet then "PrerequisiteZoneLevelTooLow"
		else nil,
		economy.UnlockCost,
		balance,
		nil
	)
	local buildStatus = status(
		unlocked and level == 0 and hasNextLevel,
		if not unlocked then "RegionLocked"
		elseif level > 0 then "RegionAlreadyBuilt"
		elseif not hasNextLevel then "MaxLevel"
		else nil,
		buildCost,
		balance,
		1
	)
	local upgradeStatus = status(
		unlocked and level >= 1 and hasNextLevel,
		if not unlocked then "RegionLocked"
		elseif level == 0 then "RegionNotBuilt"
		elseif not hasNextLevel then "MaxLevel"
		else nil,
		upgradeCost,
		balance,
		if hasNextLevel then nextLevel else nil
	)

	local constructionAction
	local constructionStatus
	if level == 0 then
		constructionAction = "Build"
		constructionStatus = buildStatus
	elseif hasNextLevel then
		constructionAction = "Upgrade"
		constructionStatus = upgradeStatus
	else
		constructionAction = "None"
		constructionStatus = status(false, "MaxLevel", 0, balance, nil)
	end

	return {
		RegionId = regionId,
		Unlocked = unlocked,
		UnlockPrerequisiteZoneId = prerequisiteZoneId,
		UnlockPrerequisiteLevel = prerequisiteLevel,
		UnlockPrerequisiteCurrentLevel = prerequisiteCurrentLevel,
		UnlockPrerequisiteMet = prerequisiteMet,
		Level = level,
		Balance = balance,
		Unlock = unlockStatus,
		Build = buildStatus,
		Upgrade = upgradeStatus,
		UnlockButtonState = buttonState(unlockStatus),
		ConstructionAction = constructionAction,
		Construction = constructionStatus,
		ConstructionButtonState = buttonState(constructionStatus),
	}
end

function IncomeZoneActionQuery.GetUnlockButtonState(player: Player, regionId: string): string
	local snapshot = IncomeZoneActionQuery.Get(player, regionId)
	return if snapshot then snapshot.UnlockButtonState else "Locked"
end

function IncomeZoneActionQuery.GetConstructionButtonState(
	player: Player,
	regionId: string
): string
	local snapshot = IncomeZoneActionQuery.Get(player, regionId)
	return if snapshot then snapshot.ConstructionButtonState else "Locked"
end

return IncomeZoneActionQuery
