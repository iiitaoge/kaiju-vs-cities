--[[
	职责：
	- 保存区域运行时状态，并作为这些 Attribute 的唯一物理写入模块。

	输入：
	- player、regionId，以及对应字段的新值。

	输出：
	- Get：Unlocked、Level、IncomeMultiplier、AutoIncome 的快照。
	- Getter：单个字段值。
	- Setter：写入后的字段值。

	读取：
	- RegionEconomyConfigs.InitialUnlocked。
	- PlayerStateService 的 Regions/<RegionId> Attributes。

	写入：
	- PlayerStateService 的 Regions/<RegionId> Attributes。

	不负责：
	- 不计算收入或价格。
	- 不负责在等级、倍率变化前结算房屋收入；业务调用方必须先结算。
]]

local Players = game:GetService("Players")

local PlayerStateService = require(script.Parent.PlayerStateService)
local RegionEconomyConfigs = require(script.Parent.RegionEconomyConfigs)

local RegionStateService = {}

local DEFAULT_LEVEL = 0
local DEFAULT_INCOME_MULTIPLIER = 1
local DEFAULT_AUTO_INCOME = false

local function getRegionState(player: Player, regionId: string): Folder
	return PlayerStateService.GetEntity(player, "Regions", regionId)
end

local function initialize(player: Player)
	for regionId, config in pairs(RegionEconomyConfigs) do
		local regionState = getRegionState(player, regionId)
		if regionState:GetAttribute("Unlocked") == nil then
			regionState:SetAttribute("Unlocked", config.InitialUnlocked)
		end

		if regionState:GetAttribute("Level") == nil then
			regionState:SetAttribute("Level", DEFAULT_LEVEL)
		end

		if regionState:GetAttribute("IncomeMultiplier") == nil then
			regionState:SetAttribute("IncomeMultiplier", DEFAULT_INCOME_MULTIPLIER)
		end

		if regionState:GetAttribute("AutoIncome") == nil then
			regionState:SetAttribute("AutoIncome", DEFAULT_AUTO_INCOME)
		end
	end
end

function RegionStateService.Start()
	Players.PlayerAdded:Connect(initialize)

	for _, player in Players:GetPlayers() do
		initialize(player)
	end
end

function RegionStateService.Get(player: Player, regionId: string)
	return {
		Unlocked = RegionStateService.GetUnlocked(player, regionId),
		Level = RegionStateService.GetLevel(player, regionId),
		IncomeMultiplier = RegionStateService.GetIncomeMultiplier(player, regionId),
		AutoIncome = RegionStateService.GetAutoIncome(player, regionId),
	}
end

function RegionStateService.GetUnlocked(player: Player, regionId: string): boolean
	local value = getRegionState(player, regionId):GetAttribute("Unlocked")
	if value ~= nil then
		return value
	end

	local config = RegionEconomyConfigs[regionId]
	return if config then config.InitialUnlocked else false
end

function RegionStateService.SetUnlocked(player: Player, regionId: string, value: boolean): boolean
	assert(type(value) == "boolean", "value 必须是 boolean")
	getRegionState(player, regionId):SetAttribute("Unlocked", value)
	return value
end

function RegionStateService.GetLevel(player: Player, regionId: string): number
	return getRegionState(player, regionId):GetAttribute("Level") or DEFAULT_LEVEL
end

function RegionStateService.SetLevel(player: Player, regionId: string, value: number): number
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value >= 0
			and value % 1 == 0,
		"value 必须是有限非负整数"
	)
	getRegionState(player, regionId):SetAttribute("Level", value)
	return value
end

function RegionStateService.GetIncomeMultiplier(player: Player, regionId: string): number
	return getRegionState(player, regionId):GetAttribute("IncomeMultiplier")
		or DEFAULT_INCOME_MULTIPLIER
end

function RegionStateService.SetIncomeMultiplier(player: Player, regionId: string, value: number): number
	assert(
		type(value) == "number" and value == value and value < math.huge and value >= 0,
		"value 必须是有限非负数"
	)
	getRegionState(player, regionId):SetAttribute("IncomeMultiplier", value)
	return value
end

function RegionStateService.GetAutoIncome(player: Player, regionId: string): boolean
	local value = getRegionState(player, regionId):GetAttribute("AutoIncome")
	return if value == nil then DEFAULT_AUTO_INCOME else value
end

function RegionStateService.SetAutoIncome(player: Player, regionId: string, value: boolean): boolean
	assert(type(value) == "boolean", "value 必须是 boolean")
	getRegionState(player, regionId):SetAttribute("AutoIncome", value)
	return value
end

return RegionStateService
