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
local UserInputService = game:GetService("UserInputService")

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
local LocalMonsterAttackCameraMarkerAccess = require(
	script.Parent.LocalMonsterAttackCameraMarkerAccess
)
local MonsterAttackCameraRemoteClient = require(
	script.Parent.MonsterAttackCameraRemoteClient
)
local MonsterDuelCameraRemoteClient = require(
	script.Parent.MonsterDuelCameraRemoteClient
)
local MonsterAttackRemoteClient = require(script.Parent.MonsterAttackRemoteClient)
local SoloAttackPanelCoordinator = require(script.Parent.SoloAttackPanelCoordinator)
local SoloAttackTargetSnapshotMapper = require(
	script.Parent.SoloAttackTargetSnapshotMapper
)
local MonsterAttackSelectionConfig = require(
	ReplicatedStorage.Shared.Monster.MonsterAttackSelectionConfig
)
local MonsterAttackCameraProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterAttackCameraProtocol
)
local MonsterDuelCameraProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterDuelCameraProtocol
)
local MonsterDuelSceneConfig = require(
	ReplicatedStorage.Shared.Monster.MonsterDuelSceneConfig
)
local MonsterDuelCameraFit = require(script.Parent.Parent.Camera.MonsterDuelCameraFit)
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
	OnPendingWorldPointChanged: ((boolean) -> ())?,
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
	SubmitPendingWorldPoint: () -> AttackPanelCoordinator.RequestResult,
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

local function failure(reason: string): AttackPanelCoordinator.RequestResult
	return {
		Succeeded = false,
		Reason = reason,
		CommandId = nil,
		Monster = nil,
	}
end

local function resolveDuelCameraCFrame(
	command: MonsterDuelCameraProtocol.CameraCommand
): CFrame
	local camera = workspace.CurrentCamera
	local autoFit = MonsterDuelSceneConfig.Camera.AutoFit
	if not camera or not autoFit.Enabled then
		return command.CameraCFrame
	end
	return MonsterDuelCameraFit.Fit(
		command.CameraCFrame,
		command.FieldOfView,
		camera.ViewportSize,
		command.CameraFitSpheres,
		autoFit.Padding
	)
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
	local followStateConnection: RBXScriptConnection? = nil
	local cameraPresentationConnection: RBXScriptConnection? = nil
	local duelCameraPresentationConnection: RBXScriptConnection? = nil
	local pendingCameraCommand = nil
	local pendingDuelCameraCommand: MonsterDuelCameraProtocol.CameraCommand? = nil
	local lastRegionCamera: {
		TargetCFrame: CFrame,
		TransitionDuration: number,
		FieldOfView: number,
	}? = nil
	local latestCameraCommandId = 0
	local latestDuelCameraCommandId = 0
	local acceptedCommandId: number? = nil
	local pendingWorldPoint: Vector3? = nil

	local function disconnectFollowState()
		if followStateConnection then
			followStateConnection:Disconnect()
			followStateConnection = nil
		end
	end

	local function disconnectCameraPresentation()
		if cameraPresentationConnection then
			cameraPresentationConnection:Disconnect()
			cameraPresentationConnection = nil
		end
		if duelCameraPresentationConnection then
			duelCameraPresentationConnection:Disconnect()
			duelCameraPresentationConnection = nil
		end
		pendingCameraCommand = nil
		pendingDuelCameraCommand = nil
	end

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

	local function notifyPendingWorldPointChanged(hasPoint: boolean)
		if callbacks.OnPendingWorldPointChanged then
			callbacks.OnPendingWorldPointChanged(hasPoint)
		end
	end

	local function clearPendingWorldPoint()
		pendingWorldPoint = nil
		if crosshairSession then
			crosshairSession.SetWorldPoint(nil)
		end
		notifyPendingWorldPointChanged(false)
	end

	local function onTargetChanged(target: Target)
		clearPendingWorldPoint()
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
			local selectableTerritories = {}
			for _, territory in target.UnlockedTerritories do
				if not territory.AttackInProgress then
					table.insert(selectableTerritories, territory)
				end
			end
			crosshairSession.SetTerritories(selectableTerritories)
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

	local function startCameraMarkerFocus(command)
		task.spawn(function()
			local markerConfig = MonsterAttackSelectionConfig.MarkerCamera
			local marker, reason
			if command.Kind == MonsterAttackCameraProtocol.FocusSoloRegionKind then
				marker, reason = LocalMonsterAttackCameraMarkerAccess.WaitByPlotName(
					command.TargetPlotName,
					command.RegionId,
					markerConfig.MarkerName,
					markerConfig.ResolveTimeout
				)
			else
				marker, reason = LocalMonsterAttackCameraMarkerAccess.Wait(
					command.TargetOwnerUserId,
					command.RegionId,
					markerConfig.MarkerName,
					markerConfig.ResolveTimeout
				)
			end
			if command.CommandId ~= latestCameraCommandId then
				return
			end
			if not marker then
				warn("怪兽攻击区域运镜找不到 CameraMarker：", reason)
				return
			end
			lastRegionCamera = {
				TargetCFrame = marker.CFrame,
				TransitionDuration = markerConfig.TransitionDuration,
				FieldOfView = markerConfig.FieldOfView,
			}
			local session = followSession
			if not session or not session.IsActive() then
				return
			end
			local focused = session.Focus({
				TargetCFrame = marker.CFrame,
				TransitionDuration = markerConfig.TransitionDuration,
				FieldOfView = markerConfig.FieldOfView,
				OnCompleted = function()
					local acknowledged = MonsterAttackCameraRemoteClient.Acknowledge(command)
					if not acknowledged then
						warn("怪兽攻击区域运镜完成回执发送失败")
					end
				end,
			})
			if not focused then
				warn("怪兽攻击区域运镜会话已结束")
			end
		end)
	end

	local function focusCameraMarker(command)
		if command.AttackerUserId ~= Players.LocalPlayer.UserId
			or command.AttackerSpawnPointId ~= spawnPointId
			or command.CommandId <= latestCameraCommandId
			or (acceptedCommandId ~= nil and command.CommandId ~= acceptedCommandId)
		then
			return
		end
		latestCameraCommandId = command.CommandId
		if not followSession then
			pendingCameraCommand = command
			return
		end
		startCameraMarkerFocus(command)
	end

	local function handleDuelCameraCommand(
		command: MonsterDuelCameraProtocol.Command
	)
		if command.Role ~= "Attacker"
			or command.AttackerUserId ~= Players.LocalPlayer.UserId
			or command.AttackerSpawnPointId ~= spawnPointId
		then
			return
		end
		if command.CommandId <= latestDuelCameraCommandId then
			return
		end
		latestDuelCameraCommandId = command.CommandId
		if command.Kind == MonsterDuelCameraProtocol.RestoreKind then
			pendingDuelCameraCommand = nil
			local session = followSession
			if session and session.IsActive() then
				if command.RestoreToRegion and lastRegionCamera then
					local regionCamera = lastRegionCamera
					local focused = session.Focus({
						TargetCFrame = regionCamera.TargetCFrame,
						TransitionDuration = regionCamera.TransitionDuration,
						FieldOfView = regionCamera.FieldOfView,
					})
					if not focused then
						warn("决斗结束后恢复区域镜头失败")
					end
				else
					session.Stop("DuelEnded")
				end
			end
			return
		end
		local session = followSession
		if not session or not session.IsActive() then
			pendingDuelCameraCommand = command
			return
		end
		local targetCFrame = resolveDuelCameraCFrame(command)
		local focused = session.Focus({
			TargetCFrame = targetCFrame,
			TransitionDuration = command.TransitionDuration,
			FieldOfView = command.FieldOfView,
			OnCompleted = function()
				local acknowledged = MonsterDuelCameraRemoteClient.Acknowledge(command)
				if not acknowledged then
					warn("攻击方决斗镜头完成回执发送失败")
				end
			end,
		})
		if not focused then
			warn("攻击方决斗镜头会话已结束")
		end
	end

	local function onAccepted(result)
		acceptedCommandId = result.CommandId
		local monster = result.Monster
		if monster and monster:IsDescendantOf(workspace) then
			local followConfig = MonsterAttackSelectionConfig.FollowCamera
			local markerConfig = MonsterAttackSelectionConfig.MarkerCamera
			disconnectFollowState()
			followSession = MonsterFollowCamera.Start(
				monster,
				{
					Offset = followConfig.Offset,
					FieldOfView = followConfig.FieldOfView,
					Responsiveness = followConfig.Responsiveness,
					RestoreDuration = markerConfig.RestoreDuration,
					OnStopped = function(reason)
						disconnectFollowState()
						disconnectCameraPresentation()
						followSession = nil
						restoreLocalPlayerCamera()
						if callbacks.OnFollowStopped then
							callbacks.OnFollowStopped(reason)
						end
					end,
				}
			)
			local function stopAfterReturn()
				if monster:GetAttribute("MonsterState") ~= "IdleAtSpawn" then
					return
				end
				local session = followSession
				if session and session.IsActive() then
					session.Stop("MonsterReturned")
				end
			end
			followStateConnection = monster:GetAttributeChangedSignal("MonsterState"):Connect(
				stopAfterReturn
			)
			stopAfterReturn()
			if pendingCameraCommand then
				local command = pendingCameraCommand
				pendingCameraCommand = nil
				if command.CommandId == acceptedCommandId then
					startCameraMarkerFocus(command)
				end
			end
			if pendingDuelCameraCommand then
				local command = pendingDuelCameraCommand
				pendingDuelCameraCommand = nil
				local session = followSession
				if session and session.IsActive() then
					local targetCFrame = resolveDuelCameraCFrame(command)
					session.Focus({
						TargetCFrame = targetCFrame,
						TransitionDuration = command.TransitionDuration,
						FieldOfView = command.FieldOfView,
						OnCompleted = function()
							local acknowledged = MonsterDuelCameraRemoteClient.Acknowledge(
								command
							)
							if not acknowledged then
								warn("攻击方决斗镜头完成回执发送失败")
							end
						end,
					})
				end
			end
			if followSession and followSession.IsActive() and callbacks.OnFollowStarted then
				callbacks.OnFollowStarted(monster)
			end
		end
		callbacks.OnAccepted()
	end

	local function onClosed(reason)
		clearPendingWorldPoint()
		stopInput()
		stopCrosshair()
		restoreBrowseCamera()
		if reason ~= "CommandAccepted" then
			disconnectCameraPresentation()
		end
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

	cameraPresentationConnection = MonsterAttackCameraRemoteClient.Observe(focusCameraMarker)
	duelCameraPresentationConnection = MonsterDuelCameraRemoteClient.Observe(
		handleDuelCameraCommand
	)

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
				clearPendingWorldPoint()
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

	local function handleWorldPoint(worldPoint: Vector3)
		if not panelSession or not panelSession.IsOpen() then
			return
		end
		if UserInputService.TouchEnabled then
			local allowed, reason = panelSession.ValidateWorldPoint(worldPoint)
			if not allowed then
				clearPendingWorldPoint()
				onValidationFailed(reason or "EntryPointUnavailable")
				return
			end
			pendingWorldPoint = worldPoint
			if crosshairSession then
				crosshairSession.SetWorldPoint(worldPoint)
			end
			notifyPendingWorldPointChanged(true)
			return
		end

		local result = panelSession.SubmitWorldPoint(worldPoint)
		diagnostics.RecordResult(result)
	end

	inputSession = WorldPointInputController.Start(
		handleWorldPoint,
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
		SubmitPendingWorldPoint = function()
			if not UserInputService.TouchEnabled then
				return failure("MobileAttackButtonUnavailable")
			end
			local worldPoint = pendingWorldPoint
			if not worldPoint then
				return failure("EntryPointUnavailable")
			end
			local result = panelSession.SubmitWorldPoint(worldPoint)
			diagnostics.RecordResult(result)
			if result.Succeeded or result.Reason == "RegionAttackInProgress" then
				clearPendingWorldPoint()
			end
			return result
		end,
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
