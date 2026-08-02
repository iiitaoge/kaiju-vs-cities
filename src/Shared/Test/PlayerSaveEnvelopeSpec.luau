local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Persistence = ReplicatedStorage.Shared.Persistence
local PlayerSaveEnvelope = require(Persistence.PlayerSaveEnvelope)
local PlayerSaveSchema = require(Persistence.PlayerSaveSchema)

local PlayerSaveEnvelopeSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "PlayerSaveEnvelopeSpec: " .. message)
end

function PlayerSaveEnvelopeSpec.Run(): boolean
	local legacy = PlayerSaveSchema.Default()
	legacy.Economy.Money = 25
	local upgraded = PlayerSaveEnvelope.Normalize(legacy)
	expect(upgraded ~= nil, "旧 V1 存档必须可升级")
	expect(upgraded.Revision == 0 and upgraded.Data.Economy.Money == 25, "旧存档升级内容错误")
	expect(upgraded.Session.Id == nil, "旧存档不得凭空获得会话")

	local current = PlayerSaveEnvelope.Normalize({
		FormatVersion = 1,
		Revision = 7,
		LastCommitId = "commit-7",
		UpdatedAt = 100,
		Session = { Id = "server-a", LeaseExpiresAt = 200 },
		Data = legacy,
	})
	expect(current ~= nil and current.Revision == 7, "当前信封规范化错误")
	expect(current.Session.Id == "server-a", "会话元数据丢失")

	local future, reason = PlayerSaveEnvelope.Normalize({ FormatVersion = 2, Data = legacy })
	expect(future == nil and reason == "FutureSaveEnvelopeVersion", "未来信封必须拒绝")
	local missingData, missingDataReason = PlayerSaveEnvelope.Normalize({
		FormatVersion = 1,
		Revision = 0,
		UpdatedAt = 0,
	})
	expect(missingData == nil and missingDataReason == "MissingSaveData", "缺失业务数据必须拒绝")
	local corrupt, corruptReason = PlayerSaveEnvelope.Normalize("bad")
	expect(corrupt == nil and corruptReason == "CorruptSaveEnvelope", "损坏信封必须拒绝")
	return true
end

return PlayerSaveEnvelopeSpec
