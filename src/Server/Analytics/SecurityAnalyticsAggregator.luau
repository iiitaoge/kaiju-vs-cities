--[[
	职责：聚合服务器网络边界拒绝，避免攻击流量逐条污染 GameAnalytics。
	输入：Start 注册刷新；Record 接收 Player、固定 Surface 和稳定 Reason。
	输出：FlushPlayer 返回发送的聚合条数。
	内部算法：按 Player + Surface + Reason 累加 60 秒 → GA Design value=count。
	不负责：裁决请求、封禁玩家、保存原始参数、记录正常玩法失败或提供安全告警。
]]

local Players = game:GetService("Players")

local GameAnalyticsConfig = require(script.Parent.GameAnalyticsConfig)
local GameAnalyticsGateway = require(script.Parent.GameAnalyticsGateway)

local SecurityAnalyticsAggregator = {}

type Entry = {
	Surface: string,
	Reason: string,
	Count: number,
}

local pending: { [Player]: { [string]: Entry } } = setmetatable({}, { __mode = "k" })
local started = false

local function segment(value: string): string
	local cleaned = string.gsub(value, "[^A-Za-z0-9%-_%.%(%)!? ]", "_")
	return string.sub(cleaned, 1, 32)
end

function SecurityAnalyticsAggregator.Record(
	player: Player,
	surface: string,
	reason: string
): boolean
	if not GameAnalyticsGateway.IsEnabled()
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or type(surface) ~= "string"
		or surface == ""
		or type(reason) ~= "string"
		or reason == ""
	then
		return false
	end

	surface = segment(surface)
	reason = segment(reason)
	local entries = pending[player]
	if not entries then
		entries = {}
		pending[player] = entries
	end
	local key = surface .. ":" .. reason
	local entry = entries[key]
	if not entry then
		entry = { Surface = surface, Reason = reason, Count = 0 }
		entries[key] = entry
	end
	entry.Count += 1
	return true
end

function SecurityAnalyticsAggregator.FlushPlayer(player: Player): number
	local entries = pending[player]
	pending[player] = nil
	if not entries then
		return 0
	end

	local flushed = 0
	for _, entry in entries do
		if GameAnalyticsGateway.LogDesign(
			player,
			string.format("Security:Rejected:%s:%s", entry.Surface, entry.Reason),
			entry.Count
		) then
			flushed += 1
		end
	end
	return flushed
end

local function flushAll()
	for player in pending do
		SecurityAnalyticsAggregator.FlushPlayer(player)
	end
end

function SecurityAnalyticsAggregator.Start()
	if started then
		return
	end
	started = true
	Players.PlayerRemoving:Connect(SecurityAnalyticsAggregator.FlushPlayer)
	task.spawn(function()
		while true do
			task.wait(GameAnalyticsConfig.SecurityFlushIntervalSeconds)
			flushAll()
		end
	end)
end

return SecurityAnalyticsAggregator
