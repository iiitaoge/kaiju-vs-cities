--[[
	职责：定义 DataStore 顶层存档信封，并兼容旧的裸 V1 业务存档。
	输入：DataStore 返回的 nil、旧业务存档或信封表。
	输出：规范化的 FormatVersion 1 信封；损坏或未来版本返回 nil 和原因。
	内部算法：先识别旧格式/信封格式，再分别规范化元数据和 PlayerSaveSchema.Data。
	不负责：会话抢占规则、DataStore、玩家状态恢复、重试或 UI。
]]

local PlayerSaveSchema = require(script.Parent.PlayerSaveSchema)

local PlayerSaveEnvelope = {}

PlayerSaveEnvelope.CurrentFormatVersion = 1

local function isNonNegativeInteger(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
		and value % 1 == 0
end

local function normalizeSession(raw)
	if type(raw) ~= "table" then
		return { Id = nil, LeaseExpiresAt = 0 }
	end
	local sessionId = if type(raw.Id) == "string" and raw.Id ~= "" then raw.Id else nil
	local leaseExpiresAt = if isNonNegativeInteger(raw.LeaseExpiresAt)
		then raw.LeaseExpiresAt
		else 0
	if not sessionId then
		leaseExpiresAt = 0
	end
	return {
		Id = sessionId,
		LeaseExpiresAt = leaseExpiresAt,
	}
end

local function wrapLegacy(raw)
	local data, reason = PlayerSaveSchema.Normalize(raw)
	if not data then
		return nil, reason
	end
	return {
		FormatVersion = PlayerSaveEnvelope.CurrentFormatVersion,
		Revision = 0,
		LastCommitId = nil,
		UpdatedAt = data.SavedAt,
		Session = { Id = nil, LeaseExpiresAt = 0 },
		Data = data,
	}, nil
end

function PlayerSaveEnvelope.Normalize(raw)
	if raw == nil then
		return wrapLegacy(nil)
	end
	if type(raw) ~= "table" then
		return nil, "CorruptSaveEnvelope"
	end

	-- 已发布的 V1 存档没有顶层 FormatVersion/Data；读取时无损升级为信封。
	if raw.FormatVersion == nil and raw.Data == nil then
		return wrapLegacy(raw)
	end

	local formatVersion = raw.FormatVersion
	if not isNonNegativeInteger(formatVersion) then
		return nil, "InvalidSaveEnvelopeVersion"
	end
	if formatVersion > PlayerSaveEnvelope.CurrentFormatVersion then
		return nil, "FutureSaveEnvelopeVersion"
	end
	if formatVersion ~= 1 then
		return nil, "UnsupportedSaveEnvelopeVersion"
	end
	if not isNonNegativeInteger(raw.Revision) then
		return nil, "InvalidSaveRevision"
	end
	if not isNonNegativeInteger(raw.UpdatedAt) then
		return nil, "InvalidSaveUpdatedAt"
	end
	if raw.LastCommitId ~= nil
		and (type(raw.LastCommitId) ~= "string" or raw.LastCommitId == "") then
		return nil, "InvalidLastCommitId"
	end
	if raw.Data == nil then
		return nil, "MissingSaveData"
	end

	local data, reason = PlayerSaveSchema.Normalize(raw.Data)
	if not data then
		return nil, reason
	end
	return {
		FormatVersion = 1,
		Revision = raw.Revision,
		LastCommitId = raw.LastCommitId,
		UpdatedAt = raw.UpdatedAt,
		Session = normalizeSession(raw.Session),
		Data = data,
	}, nil
end

return table.freeze(PlayerSaveEnvelope)
