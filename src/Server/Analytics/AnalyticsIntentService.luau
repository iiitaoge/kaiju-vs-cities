--[[
	职责：接收并验证低信任客户端 UI 分析意图。
	输入：AnalyticsIntent RemoteEvent 的白名单 Intent、稳定 SubjectId 和可选 Reason。
	输出：把合法意图交给 PlayerJourneyAnalyticsCoordinator；非法输入进入聚合安全事件。
	内部算法：数据 Ready 门禁 → 10 秒固定窗口限流 → 外形/白名单/目录身份校验。
	不负责：接受金额/等级/成功声明、直接修改玩家状态或执行任何玩法动作。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAnalyticsConfig = require(script.Parent.GameAnalyticsConfig)
local PlayerJourneyAnalyticsCoordinator = require(
	script.Parent.PlayerJourneyAnalyticsCoordinator
)
local SecurityAnalyticsAggregator = require(script.Parent.SecurityAnalyticsAggregator)
local PlayerDataReadyService = require(script.Parent.Parent.PlayerDataReadyService)
local DefenseMonsterSpawnPointStateService = require(
	script.Parent.Parent.DefenseMonsterSpawnPointStateService
)
local MonsterSpawnPointStateService = require(
	script.Parent.Parent.MonsterSpawnPointStateService
)
local RebirthButtonAccess = require(script.Parent.Parent.RebirthButtonAccess)
local ServerRemoteAccess = require(script.Parent.Parent.ServerRemoteAccess)
local AnalyticsIntentProtocol = require(
	ReplicatedStorage.Shared.Analytics.AnalyticsIntentProtocol
)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)

local AnalyticsIntentService = {}

type RateRecord = {
	WindowStartedAt: number,
	Count: number,
}

local rates: { [Player]: RateRecord } = setmetatable({}, { __mode = "k" })
local started = false

local function reject(player: Player, reason: string)
	SecurityAnalyticsAggregator.Record(player, "AnalyticsIntent", reason)
end

local function withinRateLimit(player: Player): boolean
	local now = os.clock()
	local rate = rates[player]
	if not rate or now - rate.WindowStartedAt >= GameAnalyticsConfig.IntentRateWindowSeconds then
		rates[player] = { WindowStartedAt = now, Count = 1 }
		return true
	end
	rate.Count += 1
	return rate.Count <= GameAnalyticsConfig.IntentRateLimit
end

local function isMonsterSubject(subjectId): boolean
	return type(subjectId) == "string"
		and #subjectId <= AnalyticsIntentProtocol.MaxSubjectLength
		and (MonsterSpawnPointCatalog.Get(subjectId) ~= nil
			or DefenseMonsterSlotCatalog.Get(subjectId) ~= nil)
end

local function isOffenseSubject(subjectId): boolean
	return type(subjectId) == "string"
		and #subjectId <= AnalyticsIntentProtocol.MaxSubjectLength
		and MonsterSpawnPointCatalog.Get(subjectId) ~= nil
end

local function validatePayload(player: Player, payload): (boolean, string?)
	if type(payload) ~= "table" then
		return false, "InvalidPayload"
	end
	local intent = payload.Intent
	if not AnalyticsIntentProtocol.IsKnownIntent(intent) then
		return false, "InvalidIntent"
	end
	if payload.Reason ~= nil
		and (type(payload.Reason) ~= "string"
			or payload.Reason == ""
			or #payload.Reason > AnalyticsIntentProtocol.MaxReasonLength)
	then
		return false, "InvalidReason"
	end

	local intents = AnalyticsIntentProtocol.Intents
	if intent == intents.RebirthOpened or intent == intents.RebirthExecuteClicked then
		if payload.SubjectId ~= nil then
			return false, "UnexpectedSubject"
		end
		local nearButton = RebirthButtonAccess.CheckActivation(player)
		if nearButton then
			return true, nil
		end
		return false, "RebirthDistanceRejected"
	end
	if intent == intents.AttackStartClicked
		or intent == intents.AttackTargetSelected
		or intent == intents.AttackCancelled
		or intent == intents.AttackUnavailable
		or intent == intents.AttackValidationFailed
	then
		if isOffenseSubject(payload.SubjectId) then
			if MonsterSpawnPointStateService.Get(player, payload.SubjectId).Built then
				return true, nil
			end
			return false, "AttackMonsterNotBuilt"
		end
		return false, "InvalidAttackSubject"
	end
	if isMonsterSubject(payload.SubjectId) then
		local built = if MonsterSpawnPointCatalog.Get(payload.SubjectId)
			then MonsterSpawnPointStateService.Get(player, payload.SubjectId).Built
			else DefenseMonsterSpawnPointStateService.Get(player, payload.SubjectId).Built
		if built then
			return true, nil
		end
		return false, "MonsterNotBuilt"
	end
	return false, "InvalidMonsterSubject"
end

function AnalyticsIntentService.Start()
	if started then
		return
	end
	started = true
	PlayerJourneyAnalyticsCoordinator.Start()
	local remote = ServerRemoteAccess.EnsureEvent(AnalyticsIntentProtocol.RemoteName)
	remote.OnServerEvent:Connect(function(player, payload)
		if PlayerDataReadyService.Get(player).Status ~= "Ready" then
			reject(player, "PlayerDataNotReady")
			return
		end
		if not withinRateLimit(player) then
			reject(player, "RateLimited")
			return
		end
		local valid, reason = validatePayload(player, payload)
		if not valid then
			reject(player, reason or "InvalidPayload")
			return
		end
		if not PlayerJourneyAnalyticsCoordinator.RecordClientIntent(
			player,
			payload.Intent,
			payload.SubjectId,
			payload.Reason
		) then
			reject(player, "UnhandledIntent")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		rates[player] = nil
	end)
end

return AnalyticsIntentService
