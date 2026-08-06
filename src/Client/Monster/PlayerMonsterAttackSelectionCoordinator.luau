--[[
	职责：组装玩家城市攻击与无其他玩家时的单人空地攻击选择会话。

	输入：自己的 SpawnPointId、管理状态机回调，以及可选表现回调。
	输出：切换/刷新目标、提交世界点、取消和恢复跟随视角的会话。
	内部算法：查询一次目标快照；有玩家时复用正式 AttackPanelCoordinator，
	没有其他玩家时使用 SoloAttackPanelCoordinator；两者共享俯视相机、准星、世界点击和跟随视角。

	不负责：创建 GUI、美术布局、服务器权威校验或执行战斗。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsIntentClient = require(script.Parent.Parent.Analytics.AnalyticsIntentClient)
local AttackBrowseCamera = require(script.Parent.Parent.Camera.AttackBrowseCamera)
local MonsterFollowCamera = require(script.Parent.Parent.Camera.MonsterFollowCamera)
local WorldPointInputController = require(script.Parent.Parent.Camera.WorldPointInputController)
local AttackPanelCoordinator = require(script.Parent.AttackPanelCoordinator)
local AttackSelectionCoordinateDiagnostics = require(
	script.Parent.AttackSelectionCoordinateDiagnostics
)
local AttackTargetSnapshotMapper = require(script.Parent.AttackTargetSnapshotMapper)
local LocalAttackCrosshairPresenter = require(script.Parent.LocalAttackCrosshairPresenter)
local MonsterAttackRemoteClient = require(script.Parent.MonsterAttackRemoteClient)
local SoloAttackPanelCoordinator = require(script.Parent.SoloAttackPanelCoordinator)
local SoloAttackTargetSnapshotMapper = require(
	script.Parent.SoloAttackTargetSnapshotMapper
)
local MonsterAttackSelectionConfig = require(
	ReplicatedStorage.Shared.Monster.MonsterAttackSelectionConfig
)
local AnalyticsIntentProtocol = require(
	ReplicatedStorage.Shared.Analytics.AnalyticsIntentProtocol
)

local PlayerMonsterAttackSelectionCoordinator = {}

export type Target = AttackPanelCoordinator.Target | SoloAttackPanelCoordinator.Target

export type Callbacks = {
	OnAccepted: () -> (),
	OnCancelled: () -> (),
	OnUnavailable: (string?) -> (),
	OnTargetChanged: ((Target) -> ())?,
	OnValidationFailed: ((string) -> ())?,
	OnClosed: ((string) -> ())?,
	OnFollowStarted: ((Model) -> ())?,
	OnFollowStopped: ((string) -> ())?,
}

export type Session = {
	NextTarget: () -> Target?,
	PreviousTarget: () -> Target?,
	RefreshTargets: () -> Target?,
	SubmitWorldPoint: (Vector3) -> AttackPanelCoordinator.RequestResult,
	Cancel: () -> (),
	RestoreCamera: () -> boolean,
	GetCurrentTarget: () -> Target?,
	IsOpen: () -> boolean,
}

local function mapTargets(values)
	return AttackTargetSnapshotMapper.Map(values, function(userId)
		return Players:GetPlayerByUserId(userId)
	end)
end

function PlayerMonsterAttackSelectionCoordinator.Open(
	spawnPointId: string,
	callbacks: Callbacks
): Session?
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 无效")
	assert(type(callbacks) == "table", "callbacks 必须是 table")
	assert(type(callbacks.OnAccepted) == "function", "OnAccepted 必须是 function")
	assert(type(callbacks.OnCancelled) == "function", "OnCancelled 必须是 function")
	assert(type(callbacks.OnUnavailable) == "function", "OnUnavailable 必须是 function")
	local diagnostics = AttackSelectionCoordinateDiagnostics.Start(spawnPointId)

	local query = MonsterAttackRemoteClient.QueryTargets()
	if not query.Succeeded then
		AnalyticsIntentClient.Record(
			AnalyticsIntentProtocol.Intents.AttackUnavailable,
			spawnPointId,
			query.Reason or "TargetQueryFailed"
		)
		diagnostics.End(query.Reason or "TargetQueryFailed")
		callbacks.OnUnavailable(query.Reason or "TargetQueryFailed")
		return nil
	end
	local targetCache = mapTargets(query.Targets)
	local soloTarget = nil
	if #targetCache == 0 then
		soloTarget = SoloAttackTargetSnapshotMapper.Map(query.SoloTarget)
		if not soloTarget then
			local reason = query.SoloReason or "TargetUnavailable"
			AnalyticsIntentClient.Record(
				AnalyticsIntentProtocol.Intents.AttackUnavailable,
				spawnPointId,
				reason
			)
			diagnostics.End(reason)
			callbacks.OnUnavailable(reason)
			return nil
		end
	end

	local browseSession = nil
	local followSession = nil
	local inputSession = nil
	local panelSession = nil
	local crosshairSession = nil

	-- 输入：当前 LocalPlayer 的实时 Character 与 CurrentCamera。
	-- 输出：成功把相机交还给当前 Humanoid 时返回 true；角色暂不可用时返回 false。
	-- 内部算法：先设置 CameraSubject，再切回 Custom，让默认相机控制器继续逐帧更新。
	local function restoreLocalPlayerCamera(): boolean
		local camera = workspace.CurrentCamera
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not camera or not humanoid then
			return false
		end

		camera.CameraSubject = humanoid
		camera.CameraType = Enum.CameraType.Custom
		return true
	end

	local function restoreBrowseCamera()
		local session = browseSession
		browseSession = nil
		if session and session.IsActive() then
			session.Restore()
		end
	end

	local function stopInput()
		local session = inputSession
		inputSession = nil
		if session then
			session.Stop()
			diagnostics.RecordInputController("Stopped")
		end
	end

	local function stopCrosshair()
		local session = crosshairSession
		crosshairSession = nil
		if session then
			session.Stop()
		end
	end

	local crosshairConfig = MonsterAttackSelectionConfig.Crosshair
	local crosshairTemplate = ReplicatedStorage:FindFirstChild(crosshairConfig.TemplateName)
	if crosshairTemplate and crosshairTemplate:IsA("Model") then
		local crosshairReason
		crosshairSession, crosshairReason = LocalAttackCrosshairPresenter.Start({
			Template = crosshairTemplate,
			AnimationAssetId = crosshairConfig.AnimationAssetId,
			SurfaceOffset = crosshairConfig.SurfaceOffset,
			Diagnostics = diagnostics,
		})
		if not crosshairSession then
			diagnostics.RecordCrosshair("Failed", crosshairReason)
			warn("攻击准星启动失败：" .. tostring(crosshairReason))
		end
	else
		diagnostics.RecordCrosshair("MissingTemplate", crosshairConfig.TemplateName)
		warn("找不到攻击准星模板：ReplicatedStorage/" .. crosshairConfig.TemplateName)
	end

	local function onTargetChanged(target: Target)
		local targetLabel
		if target.Player then
			targetLabel = string.format(
				"Player:%s:%d",
				target.Player.Name,
				target.Player.UserId
			)
		else
			targetLabel = "Solo"
		end
		local territoryLabels = {}
		for _, territory in target.UnlockedTerritories do
			table.insert(
				territoryLabels,
				string.format("%s/%s", territory.ZoneId, territory.BoundsId)
			)
		end
		diagnostics.RecordTarget(targetLabel, territoryLabels)
		AnalyticsIntentClient.Record(
			AnalyticsIntentProtocol.Intents.AttackTargetSelected,
			spawnPointId
		)
		if crosshairSession then
			crosshairSession.SetTerritories(target.UnlockedTerritories)
		end
		diagnostics.RecordCamera("BEFORE_TARGET")
		if browseSession then
			browseSession.SetTarget(target.AttackView)
		else
			browseSession = AttackBrowseCamera.Open(
				target.AttackView,
				MonsterAttackSelectionConfig.BrowseCamera
			)
		end
		diagnostics.RecordCamera("AFTER_TARGET")
		if callbacks.OnTargetChanged then
			callbacks.OnTargetChanged(target)
		end
	end

	local function onValidationFailed(reason)
		AnalyticsIntentClient.Record(
			AnalyticsIntentProtocol.Intents.AttackValidationFailed,
			spawnPointId,
			reason
		)
		if callbacks.OnValidationFailed then
			callbacks.OnValidationFailed(reason)
		end
	end

	local function onAccepted(result)
		local monster = result.Monster
		if monster and monster:IsDescendantOf(workspace) then
			local followConfig = MonsterAttackSelectionConfig.FollowCamera
			followSession = MonsterFollowCamera.Start(
				monster,
				{
					Offset = followConfig.Offset,
					FieldOfView = followConfig.FieldOfView,
					Responsiveness = followConfig.Responsiveness,
					OnStopped = function(reason)
						followSession = nil
						restoreLocalPlayerCamera()
						if callbacks.OnFollowStopped then
							callbacks.OnFollowStopped(reason)
						end
					end,
				}
			)
			if callbacks.OnFollowStarted then
				callbacks.OnFollowStarted(monster)
			end
		end
		callbacks.OnAccepted()
	end

	local function onClosed(reason)
		stopInput()
		stopCrosshair()
		restoreBrowseCamera()
		diagnostics.End(reason)
		if reason == "Cancelled" then
			AnalyticsIntentClient.Record(
				AnalyticsIntentProtocol.Intents.AttackCancelled,
				spawnPointId,
				reason
			)
			callbacks.OnCancelled()
		end
		if callbacks.OnClosed then
			callbacks.OnClosed(reason)
		end
	end

	if soloTarget then
		panelSession = SoloAttackPanelCoordinator.Open(spawnPointId, soloTarget, {
			RequestAttack = MonsterAttackRemoteClient.RequestSoloAttack,
			OnValidationFailed = onValidationFailed,
			OnAccepted = function(result, _target)
				onAccepted(result)
			end,
			OnClosed = onClosed,
		})
		onTargetChanged(soloTarget)
	else
		panelSession = AttackPanelCoordinator.Open(spawnPointId, {
			LocalPlayer = Players.LocalPlayer,
			GetTargets = function()
				return targetCache
			end,
			RequestAttack = MonsterAttackRemoteClient.RequestAttack,
			OnTargetChanged = onTargetChanged,
			OnTargetUnavailable = function()
				if crosshairSession then
					crosshairSession.SetTerritories({})
				end
				callbacks.OnUnavailable("TargetUnavailable")
			end,
			OnValidationFailed = onValidationFailed,
			OnAccepted = function(result, _target)
				onAccepted(result)
			end,
			OnClosed = onClosed,
		})
	end

	inputSession = WorldPointInputController.Start(
		function(worldPoint)
			if panelSession and panelSession.IsOpen() then
				local result = panelSession.SubmitWorldPoint(worldPoint)
				diagnostics.RecordResult(result)
			end
		end,
		function(snapshot)
			diagnostics.RecordInput(snapshot)
		end
	)
	diagnostics.RecordInputController("Started")

	local function restoreCamera(): boolean
		if followSession and followSession.IsActive() then
			followSession.Stop("Restored")
			followSession = nil
			return true
		end
		if browseSession and browseSession.IsActive() then
			restoreBrowseCamera()
			return true
		end
		return false
	end

	return {
		NextTarget = panelSession.NextTarget,
		PreviousTarget = panelSession.PreviousTarget,
		RefreshTargets = function()
			if soloTarget then
				return panelSession.RefreshTargets()
			end
			local response = MonsterAttackRemoteClient.QueryTargets()
			if not response.Succeeded then
				callbacks.OnUnavailable(response.Reason or "TargetQueryFailed")
				return nil
			end
			targetCache = mapTargets(response.Targets)
			return panelSession.RefreshTargets()
		end,
		SubmitWorldPoint = panelSession.SubmitWorldPoint,
		Cancel = function()
			if panelSession.IsOpen() then
				panelSession.Cancel()
			else
				restoreCamera()
			end
		end,
		RestoreCamera = restoreCamera,
		GetCurrentTarget = panelSession.GetCurrentTarget,
		IsOpen = panelSession.IsOpen,
	}
end

return PlayerMonsterAttackSelectionCoordinator
