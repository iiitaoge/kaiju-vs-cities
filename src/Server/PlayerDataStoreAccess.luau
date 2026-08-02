--[[
	职责：封装带会话租约和 Revision 条件的单次玩家 DataStore 更新。
	输入：Acquire 接收 UserId、SessionId、时间；Commit 额外接收预期 Revision、CommitId、存档和释放标记。
	输出：Succeeded、Data、Revision、Reason、Detail、Retryable。
	内部算法：Studio/线上选独立 Store → UpdateAsync 内执行纯会话规则 → 规范化提交后的信封。
	不负责：业务 Schema 生成、状态快照、调用重试、保存队列、玩家生命周期或 UI。
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Configs = require(script.Parent.PlayerPersistenceConfigs)
local PlayerSaveEnvelope = require(ReplicatedStorage.Shared.Persistence.PlayerSaveEnvelope)
local PlayerSaveSessionRules = require(ReplicatedStorage.Shared.Persistence.PlayerSaveSessionRules)

local PlayerDataStoreAccess = {}

local function isEnabled(): boolean
	return not RunService:IsStudio() or Configs.StudioEnabled
end

local function getStore()
	local storeName = if RunService:IsStudio()
		then Configs.StudioStoreName
		else Configs.ProductionStoreName
	return DataStoreService:GetDataStore(storeName)
end

local function getKey(userId: number): string
	assert(type(userId) == "number" and userId % 1 == 0, "userId 必须是整数")
	return Configs.KeyPrefix .. tostring(userId)
end

local function rejected(reason: string, retryable: boolean?)
	return {
		Succeeded = false,
		Data = nil,
		Revision = nil,
		Reason = reason,
		Detail = nil,
		Retryable = retryable == true,
	}
end

local function update(userId: number, transform)
	if not isEnabled() then
		return rejected("PersistenceDisabled", false)
	end

	local decisionReason = nil
	local succeeded, valueOrFailure = pcall(function()
		return getStore():UpdateAsync(getKey(userId), function(currentValue)
			local nextValue, reason = transform(currentValue)
			decisionReason = reason
			return nextValue
		end)
	end)
	if not succeeded then
		return {
			Succeeded = false,
			Data = nil,
			Revision = nil,
			Reason = "DataStoreError",
			Detail = tostring(valueOrFailure),
			Retryable = true,
		}
	end
	if decisionReason then
		return rejected(decisionReason, decisionReason == "SessionConflict")
	end

	local envelope, reason = PlayerSaveEnvelope.Normalize(valueOrFailure)
	if not envelope then
		return rejected(reason or "InvalidStoredEnvelope", false)
	end
	return {
		Succeeded = true,
		Data = envelope.Data,
		Revision = envelope.Revision,
		Reason = nil,
		Detail = nil,
		Retryable = false,
	}
end

function PlayerDataStoreAccess.IsEnabled(): boolean
	return isEnabled()
end

function PlayerDataStoreAccess.Acquire(userId: number, sessionId: string, now: number?)
	local acquiredAt = now or os.time()
	return update(userId, function(currentValue)
		return PlayerSaveSessionRules.Acquire(
			currentValue,
			sessionId,
			acquiredAt,
			Configs.SessionLeaseSeconds
		)
	end)
end

function PlayerDataStoreAccess.Commit(
	userId: number,
	sessionId: string,
	expectedRevision: number,
	commitId: string,
	data,
	releaseSession: boolean,
	now: number?
)
	local committedAt = now or os.time()
	return update(userId, function(currentValue)
		return PlayerSaveSessionRules.Commit(
			currentValue,
			sessionId,
			expectedRevision,
			commitId,
			data,
			committedAt,
			Configs.SessionLeaseSeconds,
			releaseSession
		)
	end)
end

return PlayerDataStoreAccess
