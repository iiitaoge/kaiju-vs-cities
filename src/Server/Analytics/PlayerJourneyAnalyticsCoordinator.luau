--[[
	职责：组合受限 UI 意图与服务器权威事实，记录核心漏斗、GA Progression 和关键数值。
	输入：RecordClientIntent 接收已校验白名单意图；其余 Record 方法接收已提交的服务器结果。
	输出：向 Roblox 原生漏斗与 GameAnalytics 提交事件；所有方法不影响业务返回值。
	内部算法：按玩家维护 Attack/Upgrade/Rebirth 会话 → 只允许相邻步骤前进；教程使用一次性漏斗。
	不负责：接收 Remote、执行业务、修改金钱/等级/存档、计算价格或信任客户端成功声明。
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAnalyticsConfig = require(script.Parent.GameAnalyticsConfig)
local GameAnalyticsGateway = require(script.Parent.GameAnalyticsGateway)
local PlayerProgressionSnapshotAnalytics = require(
	script.Parent.PlayerProgressionSnapshotAnalytics
)
local RobloxFunnelGateway = require(script.Parent.RobloxFunnelGateway)
local TutorialProgressStateService = require(
	script.Parent.Parent.TutorialProgressStateService
)
local AnalyticsIntentProtocol = require(
	ReplicatedStorage.Shared.Analytics.AnalyticsIntentProtocol
)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)
local TutorialProgression = require(
	ReplicatedStorage.Shared.Tutorial.TutorialProgression
)

local PlayerJourneyAnalyticsCoordinator = {}

type Flow = {
	SessionId: string,
	SubjectId: string?,
	LastStep: number,
}

type PlayerRecord = {
	Attack: Flow?,
	Upgrade: Flow?,
	Rebirth: Flow?,
	TutorialLastStep: number,
}

local TUTORIAL_STEPS = table.freeze({
	[1] = "Playable",
	[2] = "First City Built",
	[3] = "First Cash Collected",
	[4] = "First City Level 2",
	[5] = "First Monster Built",
	[6] = "Attack Targets Loaded",
	[7] = "Attack Target Selected",
	[8] = "First Attack Accepted",
})

local ATTACK_STEPS = table.freeze({
	[1] = "Management Opened",
	[2] = "Start Clicked",
	[3] = "Targets Loaded",
	[4] = "Target Selected",
	[5] = "Attack Requested",
	[6] = "Attack Accepted",
})

local UPGRADE_STEPS = table.freeze({
	[1] = "Management Opened",
	[2] = "Upgrade Clicked",
	[3] = "Upgrade Completed",
})

local REBIRTH_STEPS = table.freeze({
	[1] = "Panel Opened",
	[2] = "Eligible",
	[3] = "Execute Clicked",
	[4] = "Save Committed",
	[5] = "Runtime Reloaded",
})

local records: { [Player]: PlayerRecord } = setmetatable({}, { __mode = "k" })
local started = false

local function getRecord(player: Player): PlayerRecord
	local record = records[player]
	if not record then
		record = {
			Attack = nil,
			Upgrade = nil,
			Rebirth = nil,
			TutorialLastStep = 0,
		}
		records[player] = record
	end
	return record
end

local function newFlow(subjectId: string?): Flow
	return {
		SessionId = HttpService:GenerateGUID(false),
		SubjectId = subjectId,
		LastStep = 0,
	}
end

local function beginFlow(
	player: Player,
	funnelName: string,
	stepNames,
	subjectId: string?
): Flow
	local flow = newFlow(subjectId)
	if RobloxFunnelGateway.LogRecurringStep(
		player,
		funnelName,
		flow.SessionId,
		1,
		stepNames[1]
	) then
		flow.LastStep = 1
	end
	return flow
end

local function advanceFlow(
	player: Player,
	flow: Flow?,
	funnelName: string,
	stepNames,
	step: number,
	subjectId: string?
): boolean
	if not flow
		or flow.LastStep ~= step - 1
		or (subjectId ~= nil and flow.SubjectId ~= subjectId)
	then
		return false
	end
	local stepName = stepNames[step]
	if not stepName then
		return false
	end
	if not RobloxFunnelGateway.LogRecurringStep(
		player,
		funnelName,
		flow.SessionId,
		step,
		stepName
	) then
		return false
	end
	flow.LastStep = step
	return true
end

local function reasonCategory(reason: string?): string
	if type(reason) ~= "string" or reason == "" then
		return "Unknown"
	end
	local category = string.match(reason, "^[^:]+") or "Unknown"
	category = string.gsub(category, "[^A-Za-z0-9%-_%.%(%)!? ]", "_")
	return string.sub(category, 1, 32)
end

local function logTutorialStep(player: Player, step: number): boolean
	local record = getRecord(player)
	local stepName = TUTORIAL_STEPS[step]
	if not stepName
		or step <= record.TutorialLastStep
		or TutorialProgressStateService.Get(player) >= TutorialProgression.CurrentVersion
	then
		return false
	end
	if not RobloxFunnelGateway.LogOnboardingStep(player, step, stepName) then
		return false
	end
	record.TutorialLastStep = step
	GameAnalyticsGateway.LogProgression(
		player,
		"Complete",
		"Tutorial",
		"V" .. TutorialProgression.CurrentVersion,
		string.gsub(stepName, " ", "-"),
		step
	)
	return true
end

local function logBalanceAfter(
	player: Player,
	context: string,
	balance: number,
	customFields: { [string]: any }?
)
	GameAnalyticsGateway.LogDesign(
		player,
		"Metric:Economy:Balance:" .. context,
		balance,
		customFields
	)
end

function PlayerJourneyAnalyticsCoordinator.RecordPlayable(player: Player)
	logTutorialStep(player, 1)
	PlayerProgressionSnapshotAnalytics.Log(player, "Playable")
end

function PlayerJourneyAnalyticsCoordinator.RecordRegionUnlocked(
	player: Player,
	regionId: string,
	cost: number,
	balance: number
)
	GameAnalyticsGateway.LogProgression(
		player,
		"Complete",
		"Region",
		regionId,
		"Unlocked",
		0
	)
	logBalanceAfter(player, "Region", balance, {
		action = "Unlock",
		regionId = regionId,
		cost = tostring(cost),
	})
end

function PlayerJourneyAnalyticsCoordinator.RecordRegionLevel(
	player: Player,
	regionId: string,
	action: string,
	level: number,
	cost: number,
	balance: number
)
	GameAnalyticsGateway.LogProgression(
		player,
		"Complete",
		"Region",
		regionId,
		"Level-" .. level,
		level,
		{ action = action }
	)
	logBalanceAfter(player, "Region", balance, {
		action = action,
		regionId = regionId,
		level = tostring(level),
		cost = tostring(cost),
	})
	if regionId == "R1" and level == 1 then
		logTutorialStep(player, 2)
	elseif regionId == "R1" and level == 2 then
		logTutorialStep(player, 4)
	end
end

function PlayerJourneyAnalyticsCoordinator.RecordManualIncome(
	player: Player,
	collected: number,
	balance: number
)
	if collected > 0 then
		logTutorialStep(player, 3)
		logBalanceAfter(player, "ManualIncome", balance, {
			collected = tostring(collected),
		})
	end
end

function PlayerJourneyAnalyticsCoordinator.RecordBoostPurchased(
	player: Player,
	regionId: string,
	transactionKind: string,
	cost: number,
	snapshot
)
	GameAnalyticsGateway.LogProgression(
		player,
		"Complete",
		"Boost",
		regionId,
		transactionKind,
		1
	)
	logBalanceAfter(player, "Boost", snapshot.Balance, {
		regionId = regionId,
		transactionKind = transactionKind,
		cost = tostring(cost),
	})
	GameAnalyticsGateway.LogDesign(
		player,
		"Metric:Region:IncomeMultiplier:" .. regionId,
		snapshot.IncomeMultiplier
	)
	GameAnalyticsGateway.LogDesign(
		player,
		"Metric:Region:HealthMultiplier:" .. regionId,
		snapshot.HealthMultiplier
	)
	GameAnalyticsGateway.LogDesign(
		player,
		"Metric:Region:AutoIncome:" .. regionId,
		if snapshot.AutoIncome then 1 else 0
	)
end

function PlayerJourneyAnalyticsCoordinator.RecordMonsterPurchase(
	player: Player,
	spawnPointId: string,
	action: string,
	level: number,
	cost: number,
	balance: number
)
	GameAnalyticsGateway.LogProgression(
		player,
		"Complete",
		"Monster",
		spawnPointId,
		"Level-" .. level,
		level,
		{ action = action }
	)
	logBalanceAfter(player, "Monster", balance, {
		action = action,
		spawnPointId = spawnPointId,
		level = tostring(level),
		cost = tostring(cost),
	})
	if action == "Build" and spawnPointId == "M1-S1" then
		logTutorialStep(player, 5)
	end

	if action == "Upgrade" then
		local record = getRecord(player)
		if advanceFlow(
			player,
			record.Upgrade,
			GameAnalyticsConfig.MonsterUpgradeFunnelName,
			UPGRADE_STEPS,
			3,
			spawnPointId
		) then
			record.Upgrade = nil
		end
	end
end

function PlayerJourneyAnalyticsCoordinator.RecordMonsterUpgradeRejected(
	player: Player,
	spawnPointId: string,
	reason: string?
)
	GameAnalyticsGateway.LogDesign(
		player,
		"Gameplay:Monster:UpgradeRejected:" .. spawnPointId,
		nil,
		{ reason = reasonCategory(reason) }
	)
end

function PlayerJourneyAnalyticsCoordinator.RecordAttackTargetsLoaded(
	player: Player,
	targetCount: number
)
	local record = getRecord(player)
	if advanceFlow(
		player,
		record.Attack,
		GameAnalyticsConfig.AttackLaunchFunnelName,
		ATTACK_STEPS,
		3,
		record.Attack and record.Attack.SubjectId or nil
	) then
		logTutorialStep(player, 6)
	end
	GameAnalyticsGateway.LogDesign(player, "Gameplay:Attack:TargetsLoaded", targetCount)
end

function PlayerJourneyAnalyticsCoordinator.RecordAttackRequested(
	player: Player,
	spawnPointId: string
)
	local record = getRecord(player)
	advanceFlow(
		player,
		record.Attack,
		GameAnalyticsConfig.AttackLaunchFunnelName,
		ATTACK_STEPS,
		5,
		spawnPointId
	)
end

function PlayerJourneyAnalyticsCoordinator.RecordAttackAccepted(
	player: Player,
	spawnPointId: string
)
	local record = getRecord(player)
	advanceFlow(
		player,
		record.Attack,
		GameAnalyticsConfig.AttackLaunchFunnelName,
		ATTACK_STEPS,
		6,
		spawnPointId
	)
	record.Attack = nil
	logTutorialStep(player, 8)
end

function PlayerJourneyAnalyticsCoordinator.RecordAttackRejected(
	player: Player,
	spawnPointId: string,
	reason: string?
)
	GameAnalyticsGateway.LogDesign(
		player,
		"Gameplay:Attack:RequestRejected:" .. spawnPointId,
		nil,
		{ reason = reasonCategory(reason) }
	)
end

function PlayerJourneyAnalyticsCoordinator.RecordAttackFinished(
	attacker: Player,
	defender: Player?,
	report
)
	local fields = {
		endReason = tostring(report.EndReason),
		monsterKey = tostring(report.MonsterKey),
		spawnPointId = tostring(report.AttackerSpawnPointId),
	}
	GameAnalyticsGateway.LogDesign(attacker, "Metric:Attack:Duration", report.Duration, fields)
	GameAnalyticsGateway.LogDesign(
		attacker,
		"Metric:Attack:HousesDestroyed",
		#report.DestroyedHouseIds,
		fields
	)
	GameAnalyticsGateway.LogDesign(attacker, "Metric:Attack:Reward", report.RewardGranted, fields)
	GameAnalyticsGateway.LogDesign(
		attacker,
		"Metric:Attack:DefendersDefeated",
		#report.DefeatedDefenderMonsterIds,
		fields
	)
	GameAnalyticsGateway.LogDesign(attacker, "Metric:Attack:TowerHits", report.TowerHitCount, fields)
	GameAnalyticsGateway.LogDesign(
		attacker,
		"Metric:Attack:TowerDamageTaken",
		report.TowerDamageTaken,
		fields
	)
	if defender and defender.Parent == Players then
		GameAnalyticsGateway.LogDesign(
			defender,
			"Gameplay:Defense:AttackFinished:" .. report.EndReason,
			report.Duration,
			{
				housesLost = tostring(#report.DestroyedHouseIds),
				monstersDefeated = tostring(#report.DefeatedDefenderMonsterIds),
				towerDamageDealt = tostring(report.TowerDamageTaken),
			}
		)
	end
end

function PlayerJourneyAnalyticsCoordinator.RecordRebirthState(
	player: Player,
	snapshot
)
	if snapshot and snapshot.Allowed == true then
		local record = getRecord(player)
		if advanceFlow(
			player,
			record.Rebirth,
			GameAnalyticsConfig.RebirthFunnelName,
			REBIRTH_STEPS,
			2,
			nil
		) then
			GameAnalyticsGateway.LogDesign(
				player,
				"Gameplay:Rebirth:Eligible",
				snapshot.RunEarnings,
				{ nextCount = tostring(snapshot.NextCount) }
			)
		end
	end
end

function PlayerJourneyAnalyticsCoordinator.RecordRebirthSaveCommitted(
	player: Player,
	nextCount: number
)
	local record = getRecord(player)
	advanceFlow(
		player,
		record.Rebirth,
		GameAnalyticsConfig.RebirthFunnelName,
		REBIRTH_STEPS,
		4,
		nil
	)
	GameAnalyticsGateway.LogDesign(player, "Technical:Rebirth:SaveCommitted", nextCount)
end

function PlayerJourneyAnalyticsCoordinator.RecordRebirthCompleted(
	player: Player,
	newCount: number
)
	local record = getRecord(player)
	advanceFlow(
		player,
		record.Rebirth,
		GameAnalyticsConfig.RebirthFunnelName,
		REBIRTH_STEPS,
		5,
		nil
	)
	record.Rebirth = nil
	GameAnalyticsGateway.LogProgression(
		player,
		"Complete",
		"Rebirth",
		"Run",
		"Count-" .. newCount,
		newCount
	)
	GameAnalyticsGateway.LogDesign(player, "Gameplay:Rebirth:Completed", newCount)
	PlayerProgressionSnapshotAnalytics.Log(player, "RebirthComplete")
end

function PlayerJourneyAnalyticsCoordinator.RecordRebirthFailed(
	player: Player,
	count: number,
	reason: string?
)
	GameAnalyticsGateway.LogProgression(
		player,
		"Fail",
		"Rebirth",
		"Run",
		"Count-" .. (count + 1),
		count,
		{ reason = reasonCategory(reason) }
	)
	GameAnalyticsGateway.LogDesign(
		player,
		"Gameplay:Rebirth:Failed",
		count,
		{ reason = reasonCategory(reason) }
	)
end

function PlayerJourneyAnalyticsCoordinator.RecordClientIntent(
	player: Player,
	intent: string,
	subjectId: string?,
	reason: string?
): boolean
	local record = getRecord(player)
	local intents = AnalyticsIntentProtocol.Intents
	if intent == intents.MonsterManagementOpened then
		assert(subjectId)
		record.Upgrade = beginFlow(
			player,
			GameAnalyticsConfig.MonsterUpgradeFunnelName,
			UPGRADE_STEPS,
			subjectId
		)
		if MonsterSpawnPointCatalog.Get(subjectId) then
			record.Attack = beginFlow(
				player,
				GameAnalyticsConfig.AttackLaunchFunnelName,
				ATTACK_STEPS,
				subjectId
			)
		else
			record.Attack = nil
		end
		GameAnalyticsGateway.LogDesign(
			player,
			"UI:Monster:ManagementOpened:" .. subjectId
		)
		return true
	end
	if intent == intents.MonsterManagementClosed then
		GameAnalyticsGateway.LogDesign(
			player,
			"UI:Monster:ManagementClosed:" .. assert(subjectId),
			nil,
			{ reason = reasonCategory(reason) }
		)
		record.Attack = nil
		record.Upgrade = nil
		return true
	end
	if intent == intents.MonsterUpgradeClicked then
		assert(subjectId)
		advanceFlow(
			player,
			record.Upgrade,
			GameAnalyticsConfig.MonsterUpgradeFunnelName,
			UPGRADE_STEPS,
			2,
			subjectId
		)
		GameAnalyticsGateway.LogDesign(
			player,
			"UI:Monster:UpgradeClicked:" .. subjectId
		)
		return true
	end
	if intent == intents.AttackStartClicked then
		assert(subjectId)
		advanceFlow(
			player,
			record.Attack,
			GameAnalyticsConfig.AttackLaunchFunnelName,
			ATTACK_STEPS,
			2,
			subjectId
		)
		GameAnalyticsGateway.LogDesign(player, "UI:Attack:StartClicked:" .. subjectId)
		return true
	end
	if intent == intents.AttackTargetSelected then
		assert(subjectId)
		if advanceFlow(
			player,
			record.Attack,
			GameAnalyticsConfig.AttackLaunchFunnelName,
			ATTACK_STEPS,
			4,
			subjectId
		) then
			logTutorialStep(player, 7)
		end
		GameAnalyticsGateway.LogDesign(player, "UI:Attack:TargetSelected:" .. subjectId)
		return true
	end
	if intent == intents.AttackCancelled
		or intent == intents.AttackUnavailable
		or intent == intents.AttackValidationFailed
	then
		local eventName = if intent == intents.AttackCancelled
			then "Cancelled"
			else if intent == intents.AttackUnavailable then "Unavailable" else "ValidationFailed"
		GameAnalyticsGateway.LogDesign(
			player,
			"UI:Attack:" .. eventName .. ":" .. assert(subjectId),
			nil,
			{ reason = reasonCategory(reason) }
		)
		if intent ~= intents.AttackValidationFailed then
			record.Attack = nil
		end
		return true
	end
	if intent == intents.RebirthOpened then
		record.Rebirth = beginFlow(
			player,
			GameAnalyticsConfig.RebirthFunnelName,
			REBIRTH_STEPS,
			nil
		)
		GameAnalyticsGateway.LogDesign(player, "UI:Rebirth:Opened")
		return true
	end
	if intent == intents.RebirthExecuteClicked then
		advanceFlow(
			player,
			record.Rebirth,
			GameAnalyticsConfig.RebirthFunnelName,
			REBIRTH_STEPS,
			3,
			nil
		)
		GameAnalyticsGateway.LogDesign(player, "UI:Rebirth:ExecuteClicked")
		return true
	end
	return false
end

function PlayerJourneyAnalyticsCoordinator.Start()
	if started then
		return
	end
	started = true
	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
	end)
end

return PlayerJourneyAnalyticsCoordinator
