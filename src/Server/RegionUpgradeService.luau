--[[
	职责：
	- 执行区域解锁和 UpgradeRegion 购买事务。
	- 在区域等级或已建造房屋数量变化前结算旧收入。
	- 升级成功后执行 RegionUpgradeConfigs 当前等级声明的效果。

	输入：
	- Unlock / Upgrade：player、regionId。

	输出：
	- Unlock：clientAction、按钮下一状态。
	- Upgrade：结构化 UpgradeResult，明确成功状态、旧/新等级、表现配置和按钮状态。

	读取：
	- RegionEconomyConfigs、RegionUpgradeConfigs、Regions。
	- RegionStateService、HouseStateService。

	写入：
	- 通过 MoneyService 扣款。
	- 通过 RegionStateService 写 Unlocked / Level。
	- 按 HouseCatalog 的建造进度通过 HouseStateService 建造房屋。

	不负责：
	- 不计算或领取单栋房屋收入。
	- 不假定每次升级都建造下一栋房屋。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAnalyticsGateway = require(script.Parent.Analytics.GameAnalyticsGateway)
local PlayerJourneyAnalyticsCoordinator = require(
	script.Parent.Analytics.PlayerJourneyAnalyticsCoordinator
)
local EconomyMath = require(script.Parent.EconomyMath)
local HouseIncomeService = require(script.Parent.HouseIncomeService)
local HouseStateService = require(script.Parent.HouseStateService)
local MoneyService = require(script.Parent.MoneyService)
local RegionEconomyConfigs = require(script.Parent.RegionEconomyConfigs)
local RegionStateService = require(script.Parent.RegionStateService)
local RegionUpgradeConfigs = require(script.Parent.RegionUpgradeConfigs)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local IncomeBuildingProgressionRules = require(
	ReplicatedStorage.Shared.Building.IncomeBuildingProgressionRules
)

local RegionUpgradeService = {}

export type UpgradeResult = {
	Succeeded: boolean,
	Reason: string?,
	PreviousLevel: number,
	NewLevel: number?,
	PresentationId: string?,
	NextButtonState: string,
}

local function upgradeResult(
	succeeded: boolean,
	reason: string?,
	previousLevel: number,
	newLevel: number?,
	presentationId: string?,
	nextButtonState: string
): UpgradeResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		PreviousLevel = previousLevel,
		NewLevel = newLevel,
		PresentationId = presentationId,
		NextButtonState = nextButtonState,
	}
end

local function buildEligibleRegionHouses(
	player: Player,
	regionId: string,
	regionLevel: number,
	now: number
)
	for _, definition in HouseCatalog.GetAll() do
		if definition.RegionId ~= regionId then
			continue
		end
		local modelLevel = IncomeBuildingProgressionRules.ResolveModelLevel(
			regionLevel,
			definition.BuildAtRegionLevel,
			definition.RegionLevelsPerModelLevel,
			definition.MaxModelLevel
		)
		if modelLevel then
			HouseStateService.Build(player, definition.HouseId, now)
		end
	end
end

function RegionUpgradeService.Unlock(player: Player, regionId: string)
	local economyConfig = RegionEconomyConfigs[regionId]
	if not economyConfig then
		return nil, "Locked"
	end
	if RegionStateService.GetUnlocked(player, regionId) then
		return nil, "Locked"
	end

	local spendResult = MoneyService.TrySpend(player, economyConfig.UnlockCost)
	if not spendResult.Succeeded then
		return nil, "Insufficient"
	end

	RegionStateService.SetUnlocked(player, regionId, true)
	GameAnalyticsGateway.LogDesign(player, "Gameplay:Region:Unlock:" .. regionId)
	GameAnalyticsGateway.LogResource(
		player,
		"Sink",
		economyConfig.UnlockCost,
		"Region",
		"Unlock-" .. regionId
	)
	PlayerJourneyAnalyticsCoordinator.RecordRegionUnlocked(
		player,
		regionId,
		economyConfig.UnlockCost,
		spendResult.Balance
	)
	return nil, "Locked"
end

function RegionUpgradeService.Upgrade(player: Player, regionId: string)
	local upgradeConfig = RegionUpgradeConfigs[regionId]
	local economyConfig = RegionEconomyConfigs[regionId]
	if not upgradeConfig or not economyConfig then
		return upgradeResult(false, "UnknownRegion", 0, nil, nil, "Locked")
	end
	if not RegionStateService.GetUnlocked(player, regionId) then
		return upgradeResult(false, "RegionLocked", 0, nil, nil, "Locked")
	end

	local currentLevel = RegionStateService.GetLevel(player, regionId)
	local nextLevel = currentLevel + 1
	local levels = upgradeConfig.Levels
	local levelConfig = levels[nextLevel]
	if not levelConfig then
		return upgradeResult(false, "MaxLevel", currentLevel, nil, nil, "Special")
	end

	local now = os.time()
	local settlement = HouseIncomeService.SettleRegionHouses(player, regionId, now)
	if not settlement.Accepted then
		return upgradeResult(false, "SettlementRejected", currentLevel, nil, nil, "Locked")
	end

	local cost = EconomyMath.GetUpgradeCost(economyConfig, currentLevel)
	local spendResult = MoneyService.TrySpend(player, cost)
	if not spendResult.Succeeded then
		return upgradeResult(false, "InsufficientMoney", currentLevel, nil, nil, "Insufficient")
	end

	RegionStateService.SetLevel(player, regionId, nextLevel)
	buildEligibleRegionHouses(player, regionId, nextLevel, now)
	local action = if currentLevel == 0 then "Build" else "Upgrade"
	GameAnalyticsGateway.LogDesign(
		player,
		string.format("Gameplay:Region:%s:%s", action, regionId),
		nextLevel
	)
	GameAnalyticsGateway.LogResource(
		player,
		"Sink",
		cost,
		"Region",
		string.format("%s-%s-L%d", action, regionId, nextLevel)
	)
	PlayerJourneyAnalyticsCoordinator.RecordRegionLevel(
		player,
		regionId,
		action,
		nextLevel,
		cost,
		spendResult.Balance
	)

	local nextButtonState = if levels[nextLevel + 1] then "Ready" else "Special"
	return upgradeResult(
		true,
		nil,
		currentLevel,
		nextLevel,
		levelConfig.PresentationId,
		nextButtonState
	)
end

return RegionUpgradeService
