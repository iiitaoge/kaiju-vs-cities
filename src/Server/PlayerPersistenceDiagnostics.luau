--[[
	职责：记录在线玩家持久化流程的最近状态，供服务器日志和验收读取。
	输入：UserId、状态、Revision、失败原因和时间。
	输出：Get 返回只读快照；业务流程不依赖诊断结果。
	内部算法：按 UserId 覆盖最近状态，并累计连续失败次数。
	不负责：DataStore、重试、玩家状态、告警平台或 UI。
]]

local PlayerPersistenceDiagnostics = {}

local recordsByUserId = {}

local function getOrCreate(userId: number)
	local record = recordsByUserId[userId]
	if not record then
		record = {
			Status = "Unknown",
			Revision = nil,
			LastAttemptAt = nil,
			LastSuccessAt = nil,
			FailureCount = 0,
			Reason = nil,
		}
		recordsByUserId[userId] = record
	end
	return record
end

local function copy(record)
	if not record then
		return nil
	end
	return {
		Status = record.Status,
		Revision = record.Revision,
		LastAttemptAt = record.LastAttemptAt,
		LastSuccessAt = record.LastSuccessAt,
		FailureCount = record.FailureCount,
		Reason = record.Reason,
	}
end

function PlayerPersistenceDiagnostics.MarkLoading(userId: number)
	local record = getOrCreate(userId)
	record.Status = "Loading"
	record.LastAttemptAt = os.time()
	record.Reason = nil
end

function PlayerPersistenceDiagnostics.MarkReady(userId: number, revision: number)
	local record = getOrCreate(userId)
	record.Status = "Ready"
	record.Revision = revision
	record.LastSuccessAt = os.time()
	record.FailureCount = 0
	record.Reason = nil
end

function PlayerPersistenceDiagnostics.MarkDirty(userId: number)
	local record = getOrCreate(userId)
	record.Status = "Dirty"
	record.Reason = nil
end

function PlayerPersistenceDiagnostics.MarkSaving(userId: number)
	local record = getOrCreate(userId)
	record.Status = "Saving"
	record.LastAttemptAt = os.time()
end

function PlayerPersistenceDiagnostics.MarkSaved(userId: number, revision: number)
	local record = getOrCreate(userId)
	record.Status = "Saved"
	record.Revision = revision
	record.LastSuccessAt = os.time()
	record.FailureCount = 0
	record.Reason = nil
end

function PlayerPersistenceDiagnostics.MarkReleased(userId: number, revision: number)
	local record = getOrCreate(userId)
	record.Status = "Released"
	record.Revision = revision
	record.LastSuccessAt = os.time()
	record.FailureCount = 0
	record.Reason = nil
end

function PlayerPersistenceDiagnostics.MarkFailed(userId: number, reason: string)
	local record = getOrCreate(userId)
	record.Status = "Failed"
	record.LastAttemptAt = os.time()
	record.FailureCount += 1
	record.Reason = reason
end

function PlayerPersistenceDiagnostics.Get(userId: number)
	return copy(recordsByUserId[userId])
end

function PlayerPersistenceDiagnostics.Clear(userId: number)
	recordsByUserId[userId] = nil
end

return PlayerPersistenceDiagnostics
