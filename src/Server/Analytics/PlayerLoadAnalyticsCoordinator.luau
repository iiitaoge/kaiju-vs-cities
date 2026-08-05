--[[
	职责：组合存档门禁与运行时加载结果，形成 GA 技术行为和 Roblox 原生加载漏斗。
	输入：Start 注册玩家生命周期；运行时阶段由 PlayerRuntimeLoadReporter 输入。
	输出：每局记录 Joined/SaveReady/Playable 漏斗，并记录各阶段 GA 成功、失败和耗时。
	内部算法：每名玩家生成 FunnelSessionId → 等存档结果 → 累积五个必要阶段 → 全成功后只提交一次 Playable。
	不负责：执行加载、修复失败、计算玩法行为、发送经济事件或接受客户端 Ready 声明。
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local GameAnalyticsGateway = require(script.Parent.GameAnalyticsGateway)
local PlayerJourneyAnalyticsCoordinator = require(
	script.Parent.PlayerJourneyAnalyticsCoordinator
)
local PlayerRuntimeLoadReporter = require(script.Parent.PlayerRuntimeLoadReporter)
local RobloxFunnelGateway = require(script.Parent.RobloxFunnelGateway)
local PlayerDataReadyService = require(script.Parent.Parent.PlayerDataReadyService)

local PlayerLoadAnalyticsCoordinator = {}

type Record = {
	StartedAt: number,
	FunnelSessionId: string,
	SucceededStages: { [string]: boolean },
	PlayableLogged: boolean,
}

local REQUIRED_STAGES = table.freeze({
	"Save",
	"Plot",
	"City",
	"Monster",
	"DefenseMonster",
	"Character",
})
local records: { [Player]: Record } = setmetatable({}, { __mode = "k" })
local started = false

local function elapsed(record: Record): number
	return math.max(0, os.clock() - record.StartedAt)
end

local function reasonCategory(reason: string?): string
	if type(reason) ~= "string" or reason == "" then
		return "Unknown"
	end
	local category = string.match(reason, "^[^:]+") or "Unknown"
	category = string.gsub(category, "[^A-Za-z0-9%-_%.%(%)!? ]", "_")
	return string.sub(category, 1, 32)
end

local function maybeLogPlayable(player: Player, record: Record)
	if record.PlayableLogged then
		return
	end
	for _, stage in REQUIRED_STAGES do
		if not record.SucceededStages[stage] then
			return
		end
	end

	record.PlayableLogged = true
	GameAnalyticsGateway.LogDesign(
		player,
		"Technical:Load:Playable:Complete",
		elapsed(record)
	)
	RobloxFunnelGateway.LogSessionLoadStep(player, record.FunnelSessionId, 3)
	PlayerJourneyAnalyticsCoordinator.RecordPlayable(player)
end

local function recordStage(
	player: Player,
	stage: string,
	succeeded: boolean,
	reason: string?
)
	local record = records[player]
	if not record or record.PlayableLogged then
		return
	end

	local outcome = if succeeded then "Complete" else "Fail"
	local eventId = string.format("Technical:Load:%s:%s", stage, outcome)
	if not succeeded then
		eventId ..= ":" .. reasonCategory(reason)
	end
	GameAnalyticsGateway.LogDesign(player, eventId, elapsed(record), {
		reason = reasonCategory(reason),
	})

	if succeeded and not record.SucceededStages[stage] then
		record.SucceededStages[stage] = true
		if stage == "Save" then
			RobloxFunnelGateway.LogSessionLoadStep(player, record.FunnelSessionId, 2)
		end
		maybeLogPlayable(player, record)
	end
end

local function track(player: Player)
	if records[player] then
		return
	end
	local record: Record = {
		StartedAt = os.clock(),
		FunnelSessionId = HttpService:GenerateGUID(false),
		SucceededStages = {},
		PlayableLogged = false,
	}
	records[player] = record
	GameAnalyticsGateway.LogDesign(player, "Technical:Load:Joined", 0)
	RobloxFunnelGateway.LogSessionLoadStep(player, record.FunnelSessionId, 1)

	task.spawn(function()
		local ready, reason = PlayerDataReadyService.Wait(player)
		recordStage(player, "Save", ready, reason)
	end)
end

function PlayerLoadAnalyticsCoordinator.Start()
	if started then
		return
	end
	started = true

	PlayerRuntimeLoadReporter.Connect(function(player, stage, succeeded, reason)
		recordStage(player, stage, succeeded, reason)
	end)
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		track(player)
	end
end

return PlayerLoadAnalyticsCoordinator
