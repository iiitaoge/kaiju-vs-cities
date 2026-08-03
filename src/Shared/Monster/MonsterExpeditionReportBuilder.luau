--[[
	职责：把一次怪兽远征的命令上下文和执行结果规范化为不可变报告。
	输入：稳定命令上下文、pcall 状态、执行结果和结束时间。
	输出：可安全保存/查询的 Report；无效执行结果转换为明确 Failed 报告。
	内部算法：验证上下文 → 稳定去重 ID 数组 → 规范化结果 → 计算持续时间。
	不负责：运行战斗、发奖励、保存历史、Remote 或 UI。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local MonsterExpeditionReportBuilder = {}

export type Context = {
	CommandId: number,
	AttackerUserId: number,
	DefenderUserId: number,
	AttackerSpawnPointId: string,
	MonsterKey: string,
	EntryPoint: Vector3,
	StartedAt: number,
}

export type Report = {
	CommandId: number,
	AttackerUserId: number,
	DefenderUserId: number,
	AttackerSpawnPointId: string,
	MonsterKey: string,
	EntryPoint: Vector3,
	StartedAt: number,
	FinishedAt: number,
	Duration: number,
	Succeeded: boolean,
	EndReason: "Completed" | "Defeated" | "Cancelled" | "Failed",
	Reason: string?,
	DestroyedHouseIds: { string },
	RewardGranted: number,
	DefeatedDefenderMonsterIds: { string },
	AttackerDefeated: boolean,
	TowerHitCount: number,
	TowerDamageTaken: number,
}

local validEndReasons = {
	Completed = true,
	Defeated = true,
	Cancelled = true,
	Failed = true,
}

local function normalizeIds(values): { string }
	local result = {}
	local seen = {}
	if type(values) == "table" then
		for _, value in values do
			if type(value) == "string" and value ~= "" and not seen[value] then
				seen[value] = true
				table.insert(result, value)
			end
		end
	end
	return result
end

local function assertContext(context: Context)
	assert(type(context) == "table", "context 必须是 table")
	assert(type(context.CommandId) == "number" and context.CommandId >= 1, "CommandId 无效")
	assert(type(context.AttackerUserId) == "number" and context.AttackerUserId ~= 0, "AttackerUserId 无效")
	assert(type(context.DefenderUserId) == "number" and context.DefenderUserId ~= 0, "DefenderUserId 无效")
	assert(context.AttackerUserId ~= context.DefenderUserId, "攻守玩家不能相同")
	assert(type(context.AttackerSpawnPointId) == "string" and context.AttackerSpawnPointId ~= "", "SpawnPointId 无效")
	assert(type(context.MonsterKey) == "string" and context.MonsterKey ~= "", "MonsterKey 无效")
	assert(typeof(context.EntryPoint) == "Vector3", "EntryPoint 必须是 Vector3")
	assert(ValueValidation.IsFiniteNumber(context.StartedAt), "StartedAt 无效")
end

function MonsterExpeditionReportBuilder.Build(
	context: Context,
	executionSucceeded: boolean,
	executionResult,
	finishedAt: number
): Report
	assertContext(context)
	assert(type(executionSucceeded) == "boolean", "executionSucceeded 必须是 boolean")
	assert(
		ValueValidation.IsFiniteNumber(finishedAt)
			and finishedAt >= context.StartedAt,
		"finishedAt 无效"
	)

	local validResult = executionSucceeded
		and type(executionResult) == "table"
		and type(executionResult.Succeeded) == "boolean"
		and validEndReasons[executionResult.EndReason] == true
	local endReason = if validResult then executionResult.EndReason else "Failed"
	local reason = if validResult and (executionResult.Reason == nil or type(executionResult.Reason) == "string")
		then executionResult.Reason
		else if executionSucceeded then "InvalidExpeditionResult" else "ExecutionError"
	local rewardGranted = if validResult
		and ValueValidation.IsFiniteNumber(executionResult.RewardGranted)
		and executionResult.RewardGranted >= 0
		then executionResult.RewardGranted
		else 0
	local towerHitCount = if validResult
		and type(executionResult.TowerHitCount) == "number"
		and executionResult.TowerHitCount >= 0
		and executionResult.TowerHitCount % 1 == 0
		then executionResult.TowerHitCount
		else 0
	local towerDamageTaken = if validResult
		and ValueValidation.IsFiniteNumber(executionResult.TowerDamageTaken)
		and executionResult.TowerDamageTaken >= 0
		then executionResult.TowerDamageTaken
		else 0

	local destroyedHouseIds = normalizeIds(if validResult then executionResult.DestroyedHouseIds else nil)
	local defeatedDefenderMonsterIds = normalizeIds(
		if validResult then executionResult.DefeatedDefenderMonsterIds else nil
	)
	table.freeze(destroyedHouseIds)
	table.freeze(defeatedDefenderMonsterIds)
	return table.freeze({
		CommandId = context.CommandId,
		AttackerUserId = context.AttackerUserId,
		DefenderUserId = context.DefenderUserId,
		AttackerSpawnPointId = context.AttackerSpawnPointId,
		MonsterKey = context.MonsterKey,
		EntryPoint = context.EntryPoint,
		StartedAt = context.StartedAt,
		FinishedAt = finishedAt,
		Duration = finishedAt - context.StartedAt,
		Succeeded = validResult and executionResult.Succeeded,
		EndReason = endReason,
		Reason = reason,
		DestroyedHouseIds = destroyedHouseIds,
		RewardGranted = rewardGranted,
		DefeatedDefenderMonsterIds = defeatedDefenderMonsterIds,
		AttackerDefeated = validResult and executionResult.AttackerDefeated == true,
		TowerHitCount = towerHitCount,
		TowerDamageTaken = towerDamageTaken,
	})
end

return table.freeze(MonsterExpeditionReportBuilder)
