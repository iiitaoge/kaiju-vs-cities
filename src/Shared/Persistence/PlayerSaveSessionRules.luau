--[[
	职责：计算玩家存档会话的获取和提交结果。
	输入：云端旧值、当前 SessionId、时间、租约；Commit 额外接收 Revision、CommitId、业务存档和是否释放。
	输出：允许时返回新信封；拒绝时返回 nil 和稳定原因。
	内部算法：规范化旧值 → 检查活跃租约/会话/Revision → 幂等提交 → 刷新或释放租约。
	不负责：DataStore、重试、玩家、状态快照、踢出或 UI。
]]

local PlayerSaveEnvelope = require(script.Parent.PlayerSaveEnvelope)
local PlayerSaveSchema = require(script.Parent.PlayerSaveSchema)

local PlayerSaveSessionRules = {}

local function assertIdentity(value: string, name: string)
	assert(type(value) == "string" and value ~= "", name .. " 必须是非空字符串")
end

local function assertTime(value: number, name: string)
	assert(type(value) == "number" and value >= 0 and value % 1 == 0, name .. " 必须是非负整数")
end

local function assertLeaseSeconds(value: number)
	assert(type(value) == "number" and value > 0 and value % 1 == 0, "leaseSeconds 必须是正整数")
end

local function copyWithSession(envelope, sessionId: string?, leaseExpiresAt: number)
	return {
		FormatVersion = envelope.FormatVersion,
		Revision = envelope.Revision,
		LastCommitId = envelope.LastCommitId,
		UpdatedAt = envelope.UpdatedAt,
		Session = {
			Id = sessionId,
			LeaseExpiresAt = leaseExpiresAt,
		},
		Data = envelope.Data,
	}
end

function PlayerSaveSessionRules.Acquire(raw, sessionId: string, now: number, leaseSeconds: number)
	assertIdentity(sessionId, "sessionId")
	assertTime(now, "now")
	assertLeaseSeconds(leaseSeconds)

	local envelope, reason = PlayerSaveEnvelope.Normalize(raw)
	if not envelope then
		return nil, reason
	end
	local owner = envelope.Session.Id
	if owner ~= nil
		and owner ~= sessionId
		and envelope.Session.LeaseExpiresAt > now then
		return nil, "SessionConflict"
	end
	return copyWithSession(envelope, sessionId, now + leaseSeconds), nil
end

function PlayerSaveSessionRules.Commit(
	raw,
	sessionId: string,
	expectedRevision: number,
	commitId: string,
	data,
	now: number,
	leaseSeconds: number,
	releaseSession: boolean
)
	assertIdentity(sessionId, "sessionId")
	assertTime(expectedRevision, "expectedRevision")
	assertIdentity(commitId, "commitId")
	assertTime(now, "now")
	assertLeaseSeconds(leaseSeconds)
	assert(type(releaseSession) == "boolean", "releaseSession 必须是 boolean")

	local envelope, envelopeReason = PlayerSaveEnvelope.Normalize(raw)
	if not envelope then
		return nil, envelopeReason
	end

	-- UpdateAsync 可能已经写入成功但调用方只收到了网络错误；同一 CommitId 重试必须幂等。
	if envelope.LastCommitId == commitId then
		return envelope, nil
	end
	if envelope.Session.Id ~= sessionId then
		return nil, "SessionLost"
	end
	if envelope.Revision ~= expectedRevision then
		return nil, "RevisionConflict"
	end

	local normalizedData, dataReason = PlayerSaveSchema.Normalize(data)
	if not normalizedData then
		return nil, dataReason
	end
	return {
		FormatVersion = envelope.FormatVersion,
		Revision = envelope.Revision + 1,
		LastCommitId = commitId,
		UpdatedAt = now,
		Session = {
			Id = if releaseSession then nil else sessionId,
			LeaseExpiresAt = if releaseSession then 0 else now + leaseSeconds,
		},
		Data = normalizedData,
	}, nil
end

return table.freeze(PlayerSaveSessionRules)
