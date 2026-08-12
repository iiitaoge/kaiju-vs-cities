--[[
	职责：提供载具箱子的纯规则计算。
	输入：箱子概率、稀有度顺序、载具定义和 [0, 1] 随机数。
	输出：合法性结果、钻石价格或一次抽取的稀有度/载具。
	内部算法：按配置顺序做累计权重选择；同一稀有度下的载具均匀选择。
	不负责：随机数生成、货币、存档、拥有关系、Remote 或 UI。
]]

local VehicleCrateRules = {}

local function isFiniteNumber(value): boolean
	return type(value) == "number" and value == value and value < math.huge and value > -math.huge
end

local function hasVehicleForRarity(vehicleDefinitions, rarity: string): boolean
	for _, definition in vehicleDefinitions do
		if definition.Rarity == rarity then
			return true
		end
	end
	return false
end

local function isProductId(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
		and value % 1 == 0
end

function VehicleCrateRules.Validate(
	crate,
	rarityOrder,
	vehicleDefinitions
): (boolean, string?)
	if type(crate) ~= "table" then
		return false, "InvalidCrate"
	end
	if type(crate.RarityRates) ~= "table" then
		return false, "InvalidRarityRates"
	end
	if not isFiniteNumber(crate.DiamondPrice)
		or crate.DiamondPrice <= 0
		or crate.DiamondPrice % 1 ~= 0
	then
		return false, "InvalidDiamondPrice"
	end
	if not isProductId(crate.RobuxSingleProductId)
		or not isProductId(crate.RobuxFiveDrawProductId)
	then
		return false, "InvalidRobuxProductId"
	end
	if type(rarityOrder) ~= "table" or #rarityOrder == 0 then
		return false, "InvalidRarityOrder"
	end
	if type(vehicleDefinitions) ~= "table" then
		return false, "InvalidVehicleDefinitions"
	end

	local total = 0
	for _, rarity in rarityOrder do
		local rate = crate.RarityRates[rarity]
		if not isFiniteNumber(rate) or rate < 0 then
			return false, "InvalidRarityRate:" .. tostring(rarity)
		end
		total += rate
		if rate > 0 and not hasVehicleForRarity(vehicleDefinitions, rarity) then
			return false, "NoVehicleForRarity:" .. tostring(rarity)
		end
	end

	if math.abs(total - 100) > 0.000001 then
		return false, "RarityRatesMustSumTo100"
	end
	return true, nil
end

function VehicleCrateRules.GetDiamondPrice(crate, drawCount: number): number?
	if type(crate) ~= "table" or type(drawCount) ~= "number" then
		return nil
	end
	if drawCount == 1 then
		return if isFiniteNumber(crate.DiamondPrice) and crate.DiamondPrice > 0
			then crate.DiamondPrice
			else nil
	end
	return nil
end

function VehicleCrateRules.SelectRarity(
	rates,
	rarityOrder,
	roll: number
): string?
	if type(rates) ~= "table"
		or type(rarityOrder) ~= "table"
		or not isFiniteNumber(roll)
		or roll < 0
		or roll > 1
	then
		return nil
	end

	local total = 0
	for _, rarity in rarityOrder do
		local rate = rates[rarity]
		if isFiniteNumber(rate) and rate > 0 then
			total += rate
		end
	end
	if total <= 0 then
		return nil
	end

	local target = math.min(roll, 1 - 1e-12) * total
	local accumulated = 0
	for _, rarity in rarityOrder do
		local rate = rates[rarity]
		if isFiniteNumber(rate) and rate > 0 then
			accumulated += rate
			if target < accumulated then
				return rarity
			end
		end
	end
	return nil
end

function VehicleCrateRules.SelectVehicle(
	vehicleDefinitions,
	rarity: string,
	roll: number
)
	if type(vehicleDefinitions) ~= "table"
		or type(rarity) ~= "string"
		or not isFiniteNumber(roll)
		or roll < 0
		or roll > 1
	then
		return nil
	end

	local matches = {}
	for _, definition in vehicleDefinitions do
		if definition.Rarity == rarity then
			table.insert(matches, definition)
		end
	end
	if #matches == 0 then
		return nil
	end

	local index = math.floor(math.min(roll, 1 - 1e-12) * #matches) + 1
	return matches[index]
end

function VehicleCrateRules.ResolveDraw(
	crate,
	rarityOrder,
	vehicleDefinitions,
	rarityRoll: number,
	vehicleRoll: number
)
	local rarity = VehicleCrateRules.SelectRarity(crate.RarityRates, rarityOrder, rarityRoll)
	if not rarity then
		return nil, "RaritySelectionFailed"
	end
	local vehicle = VehicleCrateRules.SelectVehicle(vehicleDefinitions, rarity, vehicleRoll)
	if not vehicle then
		return nil, "VehicleSelectionFailed"
	end
	return {
		Rarity = rarity,
		Vehicle = vehicle,
	}, nil
end

return table.freeze(VehicleCrateRules)
