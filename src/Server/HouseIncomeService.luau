--[[
	职责：
	- 按单栋房屋进行懒结算和手动领取。

	输入：
	- player、houseId、结算时间 now。
	- SettleRegionHouses 额外接收 regionId。

	输出：
	- GetHouseRate：单栋名义每秒收入和区域已建造房屋数量。
	- SettleHouse：本次新增收入、结算后的 StoredMoney。
	- SettleRegionHouses：逐栋结算的数量和新增收入总和。
	- CollectHouse：目标房屋领取金额和玩家新余额。

	读取：
	- RegionEconomyConfigs
	- RegionStateService
	- HouseStateService
	- HouseCatalog

	写入：
	- 通过 HouseStateService 写 StoredMoney、LastIncomeAt。
	- 通过 MoneyService 写玩家余额。

	不负责：
	- 不建造、摧毁或复活房屋。
	- 不决定按钮执行什么动作。
	- 不提供区域公共收入池或区域领取。
	- 不实现自动领取。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyMath = require(script.Parent.EconomyMath)
local HouseStateService = require(script.Parent.HouseStateService)
local MoneyService = require(script.Parent.MoneyService)
local RegionEconomyConfigs = require(script.Parent.RegionEconomyConfigs)
local RegionStateService = require(script.Parent.RegionStateService)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)

local HouseIncomeService = {}

export type RateResult = {
	Accepted: boolean,
	Reason: string?,
	IncomePerSecond: number,
	BuiltHouseCount: number,
}

export type SettlementResult = {
	Accepted: boolean,
	Reason: string?,
	Generated: number,
	StoredMoney: number,
	SettledAt: number?,
}

export type RegionSettlementResult = {
	Accepted: boolean,
	Reason: string?,
	SettledCount: number,
	Generated: number,
}

export type CollectionResult = {
	Accepted: boolean,
	Reason: string?,
	Collected: number,
	Balance: number,
}

local function getBuiltHouseCount(player: Player, regionId: string): number
	local count = 0
	for _, definition in ipairs(HouseCatalog.GetAll()) do
		if definition.RegionId == regionId then
			local state = HouseStateService.Get(player, definition.HouseId)
			if state.LifeState ~= "Unbuilt" then
				count += 1
			end
		end
	end
	return count
end

-- 输入：player、已登记的 houseId。
-- 输出：房屋为 Alive 时的名义每秒收入；Unbuilt / Destroyed 返回 0 和明确原因。
function HouseIncomeService.GetHouseRate(player: Player, houseId: string): RateResult
	local definition = HouseCatalog.Get(houseId)
	if not definition then
		return {
			Accepted = false,
			Reason = "UnknownHouse",
			IncomePerSecond = 0,
			BuiltHouseCount = 0,
		}
	end

	local houseState = HouseStateService.Get(player, houseId)
	if houseState.LifeState == "Unbuilt" then
		return {
			Accepted = false,
			Reason = "HouseNotBuilt",
			IncomePerSecond = 0,
			BuiltHouseCount = 0,
		}
	end
	if houseState.LifeState ~= "Alive" then
		return {
			Accepted = false,
			Reason = "HouseNotAlive",
			IncomePerSecond = 0,
			BuiltHouseCount = getBuiltHouseCount(player, definition.RegionId),
		}
	end

	local config = RegionEconomyConfigs[definition.RegionId]
	if not config then
		return {
			Accepted = false,
			Reason = "MissingRegionEconomyConfig",
			IncomePerSecond = 0,
			BuiltHouseCount = 0,
		}
	end

	local regionState = RegionStateService.Get(player, definition.RegionId)
	local builtHouseCount = getBuiltHouseCount(player, definition.RegionId)
	local regionIncomePerSecond = EconomyMath.GetRegionIncomePerSecond(
		config,
		regionState.Level,
		regionState.IncomeMultiplier
	)

	return {
		Accepted = true,
		Reason = nil,
		IncomePerSecond = EconomyMath.GetHouseIncomePerSecond(
			regionIncomePerSecond,
			builtHouseCount
		),
		BuiltHouseCount = builtHouseCount,
	}
end

-- 输入：player、目标 houseId、本次结算的 Unix 秒时间。
-- 输出：本次新增收入和结算后单栋 StoredMoney；不发放到玩家余额。
function HouseIncomeService.SettleHouse(
	player: Player,
	houseId: string,
	now: number?
): SettlementResult
	local settledAt = now or os.time()
	local rateResult = HouseIncomeService.GetHouseRate(player, houseId)
	if not rateResult.Accepted then
		local storedMoney = 0
		if rateResult.Reason ~= "UnknownHouse" then
			storedMoney = HouseStateService.Get(player, houseId).StoredMoney
		end
		return {
			Accepted = false,
			Reason = rateResult.Reason,
			Generated = 0,
			StoredMoney = storedMoney,
			SettledAt = nil,
		}
	end

	local state = HouseStateService.Get(player, houseId)
	local lastIncomeAt = state.LastIncomeAt
	local generated = if lastIncomeAt == nil
		then 0
		else EconomyMath.GetAccumulatedIncome(
			rateResult.IncomePerSecond,
			lastIncomeAt,
			settledAt
		)

	local settledState, changed = HouseStateService.CreditStoredMoney(
		player,
		houseId,
		generated,
		settledAt
	)
	if not changed then
		return {
			Accepted = false,
			Reason = "HouseStateChanged",
			Generated = 0,
			StoredMoney = settledState.StoredMoney,
			SettledAt = nil,
		}
	end

	return {
		Accepted = true,
		Reason = nil,
		Generated = generated,
		StoredMoney = settledState.StoredMoney,
		SettledAt = settledAt,
	}
end

-- 输入：player、regionId、本次统一采用的结算时间。
-- 输出：逐栋调用 SettleHouse 后的成功数量和新增收入总和；不会领取任何房屋。
function HouseIncomeService.SettleRegionHouses(
	player: Player,
	regionId: string,
	now: number?
): RegionSettlementResult
	if not RegionEconomyConfigs[regionId] then
		return {
			Accepted = false,
			Reason = "MissingRegionEconomyConfig",
			SettledCount = 0,
			Generated = 0,
		}
	end

	local settledAt = now or os.time()
	local settledCount = 0
	local generated = 0

	for _, definition in ipairs(HouseCatalog.GetAll()) do
		if definition.RegionId == regionId then
			local state = HouseStateService.Get(player, definition.HouseId)
			if state.LifeState == "Alive" then
				local result = HouseIncomeService.SettleHouse(
					player,
					definition.HouseId,
					settledAt
				)
				if not result.Accepted then
					return {
						Accepted = false,
						Reason = result.Reason,
						SettledCount = settledCount,
						Generated = generated,
					}
				end

				settledCount += 1
				generated += result.Generated
			end
		end
	end

	return {
		Accepted = true,
		Reason = nil,
		SettledCount = settledCount,
		Generated = generated,
	}
end

-- 输入：player、目标 houseId、本次领取时间。
-- 输出：只领取该栋房屋的 StoredMoney，并返回领取金额和玩家新余额。
function HouseIncomeService.CollectHouse(
	player: Player,
	houseId: string,
	now: number?
): CollectionResult
	local settlement = HouseIncomeService.SettleHouse(player, houseId, now)
	if not settlement.Accepted then
		return {
			Accepted = false,
			Reason = settlement.Reason,
			Collected = 0,
			Balance = MoneyService.Get(player),
		}
	end

	local collected = HouseStateService.TakeStoredMoney(player, houseId)
	local balance = MoneyService.Add(player, collected)
	return {
		Accepted = true,
		Reason = nil,
		Collected = collected,
		Balance = balance,
	}
end

return HouseIncomeService
