--[[
	职责：把玩家当前实际自动入账的总速率镜像到 Player Attribute。
	输入：Start；Refresh 接收在线 Player。
	输出：MoneyProtocol.AutomaticIncomeRateAttributeName 与本次总速率。
	内部算法：遍历已登记房屋，只汇总所属区域已开启自动收入且房屋 Alive 的权威单栋速率。
	不负责：收入结算、修改余额、房屋 UI 或数字格式化。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseIncomeService = require(script.Parent.HouseIncomeService)
local RegionStateService = require(script.Parent.RegionStateService)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local MoneyProtocol = require(ReplicatedStorage.Shared.Economy.MoneyProtocol)

local AutomaticIncomeRatePresentationService = {}

local started = false

local function calculate(player: Player): number
	local automaticByRegion = {}
	local total = 0
	for _, definition in HouseCatalog.GetAll() do
		local automatic = automaticByRegion[definition.RegionId]
		if automatic == nil then
			automatic = RegionStateService.GetAutoIncome(player, definition.RegionId)
			automaticByRegion[definition.RegionId] = automatic
		end
		if not automatic then
			continue
		end

		local rate = HouseIncomeService.GetHouseRate(player, definition.HouseId)
		if rate.Accepted then
			total += rate.IncomePerSecond
		end
	end
	return total
end

function AutomaticIncomeRatePresentationService.Refresh(player: Player): number
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local total = calculate(player)
	player:SetAttribute(MoneyProtocol.AutomaticIncomeRateAttributeName, total)
	return total
end

function AutomaticIncomeRatePresentationService.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(AutomaticIncomeRatePresentationService.Refresh)
	for _, player in Players:GetPlayers() do
		AutomaticIncomeRatePresentationService.Refresh(player)
	end
end

return AutomaticIncomeRatePresentationService
