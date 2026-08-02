local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Persistence = ReplicatedStorage.Shared.Persistence
local PlayerSaveSessionRules = require(Persistence.PlayerSaveSessionRules)

local PlayerSaveSessionRulesSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "PlayerSaveSessionRulesSpec: " .. message)
end

function PlayerSaveSessionRulesSpec.Run(): boolean
	local acquired = PlayerSaveSessionRules.Acquire(nil, "session-a", 100, 180)
	expect(acquired ~= nil and acquired.Session.LeaseExpiresAt == 280, "首次获取租约错误")

	local conflict, conflictReason = PlayerSaveSessionRules.Acquire(acquired, "session-b", 101, 180)
	expect(conflict == nil and conflictReason == "SessionConflict", "活跃租约必须阻止其他会话")

	local takenOver = PlayerSaveSessionRules.Acquire(acquired, "session-b", 280, 180)
	expect(takenOver ~= nil and takenOver.Session.Id == "session-b", "过期租约必须允许接管")

	local saved = PlayerSaveSessionRules.Commit(
		acquired,
		"session-a",
		0,
		"commit-1",
		acquired.Data,
		120,
		180,
		false
	)
	expect(saved ~= nil and saved.Revision == 1, "提交必须增加 Revision")
	expect(saved.Session.LeaseExpiresAt == 300, "提交必须刷新租约")

	local idempotent = PlayerSaveSessionRules.Commit(
		saved,
		"session-a",
		0,
		"commit-1",
		saved.Data,
		121,
		180,
		false
	)
	expect(idempotent ~= nil and idempotent.Revision == 1, "同一 CommitId 重试不得重复增加 Revision")

	local stale, staleReason = PlayerSaveSessionRules.Commit(
		saved,
		"session-a",
		0,
		"commit-2",
		saved.Data,
		122,
		180,
		false
	)
	expect(stale == nil and staleReason == "RevisionConflict", "旧 Revision 必须拒绝")

	local released = PlayerSaveSessionRules.Commit(
		saved,
		"session-a",
		1,
		"commit-3",
		saved.Data,
		130,
		180,
		true
	)
	expect(released ~= nil and released.Session.Id == nil, "最终提交必须释放会话")
	local releasedRetry = PlayerSaveSessionRules.Commit(
		released,
		"session-a",
		1,
		"commit-3",
		released.Data,
		131,
		180,
		true
	)
	expect(releasedRetry ~= nil and releasedRetry.Revision == 2, "释放提交重试必须幂等")
	return true
end

return PlayerSaveSessionRulesSpec
