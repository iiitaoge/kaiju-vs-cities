--[[
	职责：记录玩家关键经济与成长状态的低频 GA 数值快照。
	输入：Log 接收数据 Ready 的 Player 和固定 Snapshot 原因。
	输出：返回成功交给 GA 的事件数量。
	内部算法：读取余额/重生/区域/攻防怪兽权威状态 → 逐项发送稳定 Metric Design Event。
	不负责：修改状态、计算价格、发送 Resource Event、周期调度或创建漏斗。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DefenseMonsterSpawnPointStateService = require(
	script.Parent.Parent.DefenseMonsterSpawnPointStateService
)
local GameAnalyticsGateway = require(script.Parent.GameAnalyticsGateway)
local MoneyService = require(script.Parent.Parent.MoneyService)
local MonsterSpawnPointStateService = require(
	script.Parent.Parent.MonsterSpawnPointStateService
)
local RebirthStateService = require(script.Parent.Parent.RebirthStateService)
local RegionStateService = require(script.Parent.Parent.RegionStateService)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local PlayerProgressionSnapshotAnalytics = {}

local function logValue(
	player: Player,
	eventId: string,
	value: number,
	snapshot: string
): number
	return if GameAnalyticsGateway.LogDesign(player, eventId, value, {
		snapshot = snapshot,
	}) then 1 else 0
end

function PlayerProgressionSnapshotAnalytics.Log(
	player: Player,
	snapshot: "Playable" | "RebirthComplete"
): number
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(snapshot == "Playable" or snapshot == "RebirthComplete", "snapshot 无效")

	local sent = 0
	local rebirth = RebirthStateService.Get(player)
	sent += logValue(player, "Metric:Economy:Balance", MoneyService.Get(player), snapshot)
	sent += logValue(player, "Metric:Progression:RebirthCount", rebirth.Count, snapshot)
	sent += logValue(player, "Metric:Progression:RunEarnings", rebirth.RunEarnings, snapshot)

	local unlockedCount = 0
	for _, definition in ZoneCatalog.GetAll() do
		if definition.Kind ~= "Income" then
			continue
		end
		local state = RegionStateService.Get(player, definition.ZoneId)
		local unlocked = state.Unlocked
		if unlocked then
			unlockedCount += 1
		end
		sent += logValue(
			player,
			"Metric:Region:Unlocked:" .. definition.ZoneId,
			if unlocked then 1 else 0,
			snapshot
		)
		sent += logValue(
			player,
			"Metric:Region:Level:" .. definition.ZoneId,
			state.Level,
			snapshot
		)
		sent += logValue(
			player,
			"Metric:Region:IncomeMultiplier:" .. definition.ZoneId,
			state.IncomeMultiplier,
			snapshot
		)
		sent += logValue(
			player,
			"Metric:Region:HealthMultiplier:" .. definition.ZoneId,
			state.HealthMultiplier,
			snapshot
		)
		sent += logValue(
			player,
			"Metric:Region:AutoIncome:" .. definition.ZoneId,
			if state.AutoIncome then 1 else 0,
			snapshot
		)
	end
	sent += logValue(player, "Metric:Region:UnlockedCount", unlockedCount, snapshot)

	local builtMonsterCount = 0
	for _, definition in MonsterSpawnPointCatalog.GetAll() do
		local state = MonsterSpawnPointStateService.Get(player, definition.SpawnPointId)
		if state.Built then
			builtMonsterCount += 1
		end
		sent += logValue(
			player,
			"Metric:Monster:Level:" .. definition.SpawnPointId,
			if state.Built then state.Level else 0,
			snapshot
		)
	end
	for _, definition in DefenseMonsterSlotCatalog.GetAll() do
		local state = DefenseMonsterSpawnPointStateService.Get(
			player,
			definition.SpawnPointId
		)
		if state.Built then
			builtMonsterCount += 1
		end
		sent += logValue(
			player,
			"Metric:Monster:Level:" .. definition.SpawnPointId,
			if state.Built then state.Level else 0,
			snapshot
		)
	end
	sent += logValue(player, "Metric:Monster:BuiltCount", builtMonsterCount, snapshot)
	return sent
end

return table.freeze(PlayerProgressionSnapshotAnalytics)
