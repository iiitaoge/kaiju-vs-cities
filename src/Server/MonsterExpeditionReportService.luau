--[[
	职责：保存每名在线玩家每个怪兽出生点最近完成的一份远征报告。
	输入：攻击者 Player 和不可变报告；查询额外接收 SpawnPointId/CommandId。
	输出：最近报告或与 CommandId 精确匹配的报告。
	内部算法：Player 弱键 → SpawnPointId 单槽覆盖，避免长会话无限增长。
	不负责：构建报告、战斗、奖励、持久化、Remote 或 UI。
]]

local MonsterExpeditionReportService = {}

local latestByPlayer: { [Player]: { [string]: any } } = setmetatable({}, { __mode = "k" })

local function assertIdentity(player: Player, spawnPointId: string)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 必须是非空字符串")
end

function MonsterExpeditionReportService.Store(player: Player, report)
	assert(type(report) == "table", "report 必须是 table")
	assertIdentity(player, report.AttackerSpawnPointId)
	assert(report.AttackerUserId == player.UserId, "报告攻击者与 player 不匹配")
	assert(type(report.CommandId) == "number" and report.CommandId >= 1, "报告 CommandId 无效")
	local reports = latestByPlayer[player]
	if not reports then
		reports = {}
		latestByPlayer[player] = reports
	end
	reports[report.AttackerSpawnPointId] = report
	return report
end

function MonsterExpeditionReportService.GetLatest(player: Player, spawnPointId: string)
	assertIdentity(player, spawnPointId)
	local reports = latestByPlayer[player]
	return if reports then reports[spawnPointId] else nil
end

function MonsterExpeditionReportService.Get(
	player: Player,
	spawnPointId: string,
	commandId: number
)
	assertIdentity(player, spawnPointId)
	assert(type(commandId) == "number" and commandId >= 1, "commandId 无效")
	local report = MonsterExpeditionReportService.GetLatest(player, spawnPointId)
	return if report and report.CommandId == commandId then report else nil
end

function MonsterExpeditionReportService.Clear(player: Player): number
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local reports = latestByPlayer[player]
	local count = 0
	if reports then
		for _ in reports do
			count += 1
		end
	end
	latestByPlayer[player] = nil
	return count
end

return MonsterExpeditionReportService
