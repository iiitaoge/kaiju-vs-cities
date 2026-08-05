--[[
	职责：把本地 UI 意图发送到服务器的受限分析入口。
	输入：Record 接收共享白名单 Intent、可选稳定 SubjectId 和稳定 Reason。
	输出：事件是否已交给 RemoteEvent；Remote 不可用或参数无效时返回 false。
	内部算法：Start 缓存唯一 Remote → Record 做客户端预校验 → FireServer。
	不负责：发送金额/等级、判断业务成功、直接调用分析 SDK 或决定漏斗步骤。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsIntentProtocol = require(
	ReplicatedStorage.Shared.Analytics.AnalyticsIntentProtocol
)

local AnalyticsIntentClient = {}

local remote: RemoteEvent? = nil
local started = false

function AnalyticsIntentClient.Start(): boolean
	if started then
		return remote ~= nil
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local instance = remotes and remotes:WaitForChild(
		AnalyticsIntentProtocol.RemoteName,
		10
	)
	if not instance or not instance:IsA("RemoteEvent") then
		warn("分析 UI 意图 RemoteEvent 不可用")
		return false
	end
	remote = instance
	return true
end

function AnalyticsIntentClient.Record(
	intent: string,
	subjectId: string?,
	reason: string?
): boolean
	if not AnalyticsIntentProtocol.IsKnownIntent(intent)
		or (subjectId ~= nil
			and (type(subjectId) ~= "string"
				or subjectId == ""
				or #subjectId > AnalyticsIntentProtocol.MaxSubjectLength))
		or (reason ~= nil
			and (type(reason) ~= "string"
				or reason == ""
				or #reason > AnalyticsIntentProtocol.MaxReasonLength))
	then
		return false
	end
	if not remote and not AnalyticsIntentClient.Start() then
		return false
	end
	assert(remote):FireServer({
		Intent = intent,
		SubjectId = subjectId,
		Reason = reason,
	})
	return true
end

return AnalyticsIntentClient
