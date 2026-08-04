--[[
	职责：聚合每秒自动收入，避免向 GameAnalytics 发送高频 Resource 事件。
	输入：Start 注册周期刷新；RecordAutoIncome 接收已成功领取的玩家、区域和金额。
	输出：FlushPlayer 返回交给 GA 的聚合条数；GA 未启用或金额为零时不记录。
	内部算法：按 Player + RegionId 累加 60 秒 → 发送单条 Money/Income Source。
	不负责：领取收入、计算金额、记录低频支出或改变玩家余额。
]]

local Players = game:GetService("Players")

local GameAnalyticsConfig = require(script.Parent.GameAnalyticsConfig)
local GameAnalyticsGateway = require(script.Parent.GameAnalyticsGateway)

local GameAnalyticsEconomyAggregator = {}

local pending: { [Player]: { [string]: number } } = setmetatable({}, { __mode = "k" })
local started = false

function GameAnalyticsEconomyAggregator.RecordAutoIncome(
	player: Player,
	regionId: string,
	amount: number
): boolean
	if not GameAnalyticsGateway.IsEnabled()
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or type(regionId) ~= "string"
		or regionId == ""
		or type(amount) ~= "number"
		or amount ~= amount
		or amount == math.huge
		or amount <= 0
	then
		return false
	end

	local byRegion = pending[player]
	if not byRegion then
		byRegion = {}
		pending[player] = byRegion
	end
	byRegion[regionId] = (byRegion[regionId] or 0) + amount
	return true
end

function GameAnalyticsEconomyAggregator.FlushPlayer(player: Player): number
	local byRegion = pending[player]
	pending[player] = nil
	if not byRegion then
		return 0
	end

	local flushed = 0
	for regionId, amount in byRegion do
		if GameAnalyticsGateway.LogResource(
			player,
			"Source",
			amount,
			"Income",
			"Auto-" .. regionId
		) then
			flushed += 1
		end
	end
	return flushed
end

local function flushAll()
	for player in pending do
		GameAnalyticsEconomyAggregator.FlushPlayer(player)
	end
end

function GameAnalyticsEconomyAggregator.Start()
	if started then
		return
	end
	started = true
	Players.PlayerRemoving:Connect(GameAnalyticsEconomyAggregator.FlushPlayer)
	task.spawn(function()
		while true do
			task.wait(GameAnalyticsConfig.AutoIncomeFlushIntervalSeconds)
			flushAll()
		end
	end)
end

return GameAnalyticsEconomyAggregator
