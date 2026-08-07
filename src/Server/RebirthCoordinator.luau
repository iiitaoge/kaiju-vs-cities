--[[
	职责：编排一次玩家重生的资格、持久化提交和当前服务器运行时重载。
	输入：GetState/Execute 接收在线且数据 Ready 的 Player。
	输出：完整 UI 状态快照；失败时包含稳定 Reason。
	内部算法：状态机防重入 → 检查资格 → 原子提交默认档+新次数 → 卸载旧运行时 → 应用并重载。
	安全规则：提交结果不确定或提交后重载失败时踢出玩家，让下次加入从已提交档恢复。
	不负责：Remote、按钮距离、UI 实例；五项倍率由各权威消费入口统一查询并应用。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutomaticIncomeRatePresentationService = require(
	script.Parent.AutomaticIncomeRatePresentationService
)
local DiamondService = require(script.Parent.DiamondService)
local MonsterExpeditionReportService = require(script.Parent.MonsterExpeditionReportService)
local PlayerJourneyAnalyticsCoordinator = require(
	script.Parent.Analytics.PlayerJourneyAnalyticsCoordinator
)
local MonsterSpawnPointPurchaseCoordinator = require(
	script.Parent.MonsterSpawnPointPurchaseCoordinator
)
local PlayerCityRuntimeCoordinator = require(script.Parent.PlayerCityRuntimeCoordinator)
local PlayerDefenseMonsterRuntimeCoordinator = require(
	script.Parent.PlayerDefenseMonsterRuntimeCoordinator
)
local PlayerPlotSpawnService = require(script.Parent.PlayerPlotSpawnService)
local PlayerMonsterRuntimeCoordinator = require(script.Parent.PlayerMonsterRuntimeCoordinator)
local PlayerPersistenceCoordinator = require(script.Parent.PlayerPersistenceCoordinator)
local PlayerRegionTransactionLock = require(script.Parent.PlayerRegionTransactionLock)
local PlayerSaveStateAdapter = require(script.Parent.PlayerSaveStateAdapter)
local PlayerZoneSceneVisibilityService = require(
	script.Parent.PlayerZoneSceneVisibilityService
)
local RebirthActionQuery = require(script.Parent.RebirthActionQuery)
local RebirthResetRules = require(
	ReplicatedStorage.Shared.Progression.RebirthResetRules
)
local RebirthStateMachine = require(
	ReplicatedStorage.Shared.Progression.RebirthStateMachine
)
local SevenDayRewardStateService = require(script.Parent.SevenDayRewardStateService)

local RebirthCoordinator = {}

local states: { [Player]: RebirthStateMachine.State } = setmetatable({}, { __mode = "k" })

local function currentState(player: Player): RebirthStateMachine.State
	local state = states[player]
	if not state then
		state = RebirthStateMachine.New()
		states[player] = state
	end
	return state
end

local function apply(player: Player, event)
	local transition = RebirthStateMachine.Apply(currentState(player), event)
	states[player] = transition.State
	return transition
end

local function snapshot(player: Player, statusOverride: string?, reasonOverride: string?)
	local query = RebirthActionQuery.Get(player)
	local mode = currentState(player).Mode
	local status = statusOverride
	if not status then
		if mode == "CheckingEligibility"
			or mode == "AwaitingConfirmation"
			or mode == "Committing"
			or mode == "ReloadingRuntime" then
			status = "Processing"
		elseif mode == "RecoveryRequired" then
			status = "Failed"
		else
			status = if query.Allowed then "Ready" else "Insufficient"
		end
	end
	return {
		Status = status,
		Reason = reasonOverride or currentState(player).LastReason or query.Reason,
		Allowed = query.Allowed,
		Count = query.Count,
		NextCount = query.NextCount,
		RunEarnings = query.RunEarnings,
		RequiredRunEarnings = query.RequiredRunEarnings,
		RemainingRunEarnings = query.RemainingRunEarnings,
		CurrentBonuses = query.CurrentBonuses,
		NextBonuses = query.NextBonuses,
	}
end

local function reloadRuntime(player: Player, data): (boolean, string?)
	PlayerMonsterRuntimeCoordinator.Unload(player)
	PlayerDefenseMonsterRuntimeCoordinator.Unload(player)
	PlayerCityRuntimeCoordinator.Unload(player)
	MonsterExpeditionReportService.Clear(player)

	local applied, applyError = pcall(PlayerSaveStateAdapter.Apply, player, data, os.time())
	if not applied then
		return false, "StateApplyFailed:" .. tostring(applyError)
	end
	AutomaticIncomeRatePresentationService.Refresh(player)

	local visibility = PlayerZoneSceneVisibilityService.ApplyAll(player)
	if not visibility.Succeeded then
		return false, visibility.Reason or "ZoneVisibilityReloadFailed"
	end
	local city = PlayerCityRuntimeCoordinator.Load(player)
	if not city.Succeeded then
		return false, city.Reason or "CityRuntimeReloadFailed"
	end
	local monsters = PlayerMonsterRuntimeCoordinator.Load(player)
	if not monsters.Succeeded then
		return false, monsters.Reason or "MonsterRuntimeReloadFailed"
	end
	local defenseMonsters = PlayerDefenseMonsterRuntimeCoordinator.Load(player)
	if not defenseMonsters.Succeeded then
		return false, defenseMonsters.Reason or "DefenseMonsterRuntimeReloadFailed"
	end

	local characterReloaded, characterError = PlayerPlotSpawnService.ReloadCharacter(player)
	if not characterReloaded then
		return false, "CharacterReloadFailed:" .. tostring(characterError or "Unknown")
	end
	return true, nil
end

local function recoverByRejoin(player: Player, message: string)
	task.delay(0.25, function()
		if player.Parent == Players then
			player:Kick(message)
		end
	end)
end

function RebirthCoordinator.GetState(player: Player)
	return snapshot(player, nil, nil)
end

local function executeLocked(player: Player)
	local began = apply(player, { Kind = "Begin" })
	if not began.Accepted then
		return snapshot(player, nil, began.Reason)
	end

	local query = RebirthActionQuery.Get(player)
	local eligibility = apply(player, {
		Kind = "EligibilityResolved",
		CycleId = began.State.CycleId,
		Allowed = query.Allowed,
		Reason = query.Reason,
	})
	if not query.Allowed then
		PlayerJourneyAnalyticsCoordinator.RecordRebirthFailed(
			player,
			query.Count,
			query.Reason
		)
		return snapshot(player, "Insufficient", query.Reason)
	end

	local confirmed = apply(player, {
		Kind = "Confirm",
		CycleId = eligibility.State.CycleId,
	})
	if not confirmed.Accepted then
		PlayerJourneyAnalyticsCoordinator.RecordRebirthFailed(
			player,
			query.Count,
			confirmed.Reason
		)
		return snapshot(player, "Failed", confirmed.Reason)
	end

	local resetData = RebirthResetRules.Create(query.Count, os.time(), {
		Diamond = DiamondService.Get(player),
		DailyReward = SevenDayRewardStateService.Get(player),
	})
	local committed = PlayerPersistenceCoordinator.CommitReplacement(player, resetData)
	if not committed.Succeeded then
		local eventKind = if committed.Uncertain then "CommitUncertain" else "CommitFailed"
		apply(player, {
			Kind = eventKind,
			CycleId = confirmed.State.CycleId,
			Reason = committed.Reason,
		})
		if committed.Uncertain then
			recoverByRejoin(
				player,
				"重生存档正在安全恢复，请重新加入游戏。"
			)
		end
		PlayerJourneyAnalyticsCoordinator.RecordRebirthFailed(
			player,
			query.Count,
			committed.Reason
		)
		return snapshot(player, "Failed", committed.Reason)
	end
	PlayerJourneyAnalyticsCoordinator.RecordRebirthSaveCommitted(
		player,
		query.NextCount
	)

	local committedTransition = apply(player, {
		Kind = "CommitSucceeded",
		CycleId = confirmed.State.CycleId,
	})
	local reloaded, reloadReason = reloadRuntime(player, resetData)
	if not reloaded then
		apply(player, {
			Kind = "RuntimeReloadFailed",
			CycleId = committedTransition.State.CycleId,
			Reason = reloadReason,
		})
		recoverByRejoin(player, "重生已保存，请重新加入以完成场景重载。")
		PlayerJourneyAnalyticsCoordinator.RecordRebirthFailed(
			player,
			query.Count,
			reloadReason
		)
		return snapshot(player, "Failed", reloadReason)
	end

	apply(player, {
		Kind = "RuntimeReloadSucceeded",
		CycleId = committedTransition.State.CycleId,
	})
	PlayerJourneyAnalyticsCoordinator.RecordRebirthCompleted(
		player,
		query.NextCount
	)
	return snapshot(player, nil, nil)
end

function RebirthCoordinator.Execute(player: Player)
	local releaseRegions = PlayerRegionTransactionLock.TryAcquireExclusive(player)
	if not releaseRegions then
		return snapshot(player, "Failed", "ActionBusy")
	end
	local releaseMonsters = MonsterSpawnPointPurchaseCoordinator.TryAcquireExclusive(player)
	if not releaseMonsters then
		releaseRegions()
		return snapshot(player, "Failed", "ActionBusy")
	end

	local succeeded, resultOrError = xpcall(function()
		return executeLocked(player)
	end, debug.traceback)
	local keepSaveLocked = not succeeded
		or currentState(player).Mode == "RecoveryRequired"
	PlayerPersistenceCoordinator.FinishReplacement(player, keepSaveLocked)
	releaseMonsters()
	releaseRegions()
	if not succeeded then
		warn(string.format("玩家重生事务异常：%s (%s)", player.Name, tostring(resultOrError)))
		recoverByRejoin(player, "重生状态需要安全恢复，请重新加入游戏。")
		return snapshot(player, "Failed", "RebirthTransactionError")
	end
	return resultOrError
end

function RebirthCoordinator.Start()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return RebirthCoordinator
