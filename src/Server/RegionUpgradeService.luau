--[[
	职责：
	- 执行区域解锁和 UpgradeRegion 购买事务。
	- 在区域等级或已建造房屋数量变化前结算旧收入。
	- 升级成功后执行 RegionUpgradeConfigs 当前等级声明的效果。

	输入：
	- Unlock / Upgrade：player、regionId。

	输出：
	- Unlock：clientAction、按钮下一状态。
	- Upgrade：当前等级 ClientAction、按钮下一状态。
	- 失败时 clientAction 为 nil，第二返回值为 "Locked" 或 "Insufficient"。

	读取：
	- RegionEconomyConfigs、RegionUpgradeConfigs、Regions。
	- RegionStateService、HouseStateService。

	写入：
	- 通过 MoneyService 扣款。
	- 通过 RegionStateService 写 Unlocked / Level。
	- 按等级配置通过 HouseStateService 建造房屋。

	不负责：
	- 不计算或领取单栋房屋收入。
	- 不假定每次升级都建造下一栋房屋。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyMath = require(script.Parent.EconomyMath)
local HouseIncomeService = require(script.Parent.HouseIncomeService)
local HouseStateService = require(script.Parent.HouseStateService)
local MoneyService = require(script.Parent.MoneyService)
local RegionEconomyConfigs = require(script.Parent.RegionEconomyConfigs)
local RegionStateService = require(script.Parent.RegionStateService)
local RegionUpgradeConfigs = require(script.Parent.RegionUpgradeConfigs)
local IncomeZoneConfigs = require(ReplicatedStorage.Shared.Building.IncomeZoneConfigs)

local RegionUpgradeService = {}

local function buildRegionHouses(player: Player, regionId: string, now: number)
	for _, houses in pairs(IncomeZoneConfigs[regionId].Groups) do
		for _, house in ipairs(houses) do
			HouseStateService.Build(player, house.HouseId, now)
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
	return nil, "Locked"
end

function RegionUpgradeService.Upgrade(player: Player, regionId: string)
	local upgradeConfig = RegionUpgradeConfigs[regionId]
	local economyConfig = RegionEconomyConfigs[regionId]
	if not upgradeConfig or not economyConfig then
		return nil, "Locked"
	end
	if not RegionStateService.GetUnlocked(player, regionId) then
		return nil, "Locked"
	end

	local currentLevel = RegionStateService.GetLevel(player, regionId)
	local nextLevel = currentLevel + 1
	local levels = upgradeConfig.Levels
	local levelConfig = levels[nextLevel]
	if not levelConfig then
		return nil, "Locked"
	end

	local now = os.time()
	local settlement = HouseIncomeService.SettleRegionHouses(player, regionId, now)
	if not settlement.Accepted then
		return nil, "Locked"
	end

	local cost = EconomyMath.GetUpgradeCost(economyConfig, currentLevel)
	local spendResult = MoneyService.TrySpend(player, cost)
	if not spendResult.Succeeded then
		return nil, "Insufficient"
	end

	RegionStateService.SetLevel(player, regionId, nextLevel)

	if levelConfig.HouseAction == "Build" then
		buildRegionHouses(player, regionId, now)
	end

	local nextButtonState = if levels[nextLevel + 1] then "Ready" else "Locked"
	return levelConfig.ClientAction, nextButtonState
end

return RegionUpgradeService
