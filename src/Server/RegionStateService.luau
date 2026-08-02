--[[
	职责：
	- 保留产钱区域现有 API。
	- 通用 Unlocked/Level 委托给 ZoneStateService。
	- 只直接保存产钱系统专有的 IncomeMultiplier 和 AutoIncome。

	输入：
	- player、regionId，以及对应字段的新值。

	输出：
	- Get：Unlocked、Level、IncomeMultiplier、AutoIncome 快照。
	- Getter/Setter：对应字段值。

	不负责：
	- 不计算收入或价格，不解释其他 Zone Kind。
]]

local Players = game:GetService("Players")

local PlayerStateService = require(script.Parent.PlayerStateService)
local RegionEconomyConfigs = require(script.Parent.RegionEconomyConfigs)
local ZoneStateService = require(script.Parent.ZoneStateService)

local RegionStateService = {}

local DEFAULT_INCOME_MULTIPLIER = 1
local DEFAULT_AUTO_INCOME = false

local function getRegionState(player: Player, regionId: string): Folder
	assert(RegionEconomyConfigs[regionId], string.format("未知产钱 Zone：%s", tostring(regionId)))
	return PlayerStateService.GetEntity(player, "Zones", regionId)
end

local function initialize(player: Player)
	for regionId in pairs(RegionEconomyConfigs) do
		local regionState = getRegionState(player, regionId)
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
		Unlocked = ZoneStateService.GetUnlocked(player, regionId),
		Level = ZoneStateService.GetLevel(player, regionId),
		IncomeMultiplier = RegionStateService.GetIncomeMultiplier(player, regionId),
		AutoIncome = RegionStateService.GetAutoIncome(player, regionId),
	}
end

function RegionStateService.GetUnlocked(player: Player, regionId: string): boolean
	return ZoneStateService.GetUnlocked(player, regionId)
end


function RegionStateService.SetUnlocked(player: Player, regionId: string, value: boolean): boolean
	return ZoneStateService.SetUnlocked(player, regionId, value)
end

function RegionStateService.GetLevel(player: Player, regionId: string): number
	return ZoneStateService.GetLevel(player, regionId)
end

function RegionStateService.SetLevel(player: Player, regionId: string, value: number): number
	return ZoneStateService.SetLevel(player, regionId, value)
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
