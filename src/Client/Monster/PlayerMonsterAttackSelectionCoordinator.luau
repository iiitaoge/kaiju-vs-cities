--[[
	职责：组装正式的客户端攻击目标选择会话。

	输入：自己的 SpawnPointId、管理状态机回调，以及可选表现回调。
	输出：切换/刷新目标、提交世界点、取消和恢复跟随视角的会话。
	内部算法：查询一次目标快照并建立缓存，复用 AttackPanelCoordinator 管理选择状态；
	目标变化时切换总领地视角和准星合法范围，监听屏幕世界点击，服务器接受后跟随出征怪兽。

	不负责：创建 GUI、美术布局、服务器权威校验或执行战斗。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackBrowseCamera = require(script.Parent.Parent.Camera.AttackBrowseCamera)
local MonsterFollowCamera = require(script.Parent.Parent.Camera.MonsterFollowCamera)
local WorldPointInputController = require(script.Parent.Parent.Camera.WorldPointInputController)
local AttackPanelCoordinator = require(script.Parent.AttackPanelCoordinator)
local AttackTargetSnapshotMapper = require(script.Parent.AttackTargetSnapshotMapper)
local LocalAttackCrosshairPresenter = require(script.Parent.LocalAttackCrosshairPresenter)
local MonsterAttackRemoteClient = require(script.Parent.MonsterAttackRemoteClient)
local MonsterAttackSelectionConfig = require(
	ReplicatedStorage.Shared.Monster.MonsterAttackSelectionConfig
)

local PlayerMonsterAttackSelectionCoordinator = {}

export type Callbacks = {
	OnAccepted: () -> (),
	OnCancelled: () -> (),
	OnUnavailable: (string?) -> (),
	OnTargetChanged: ((AttackPanelCoordinator.Target) -> ())?,
	OnValidationFailed: ((string) -> ())?,
	OnClosed: ((string) -> ())?,
	OnFollowStarted: ((Model) -> ())?,
	OnFollowStopped: ((string) -> ())?,
}

export type Session = {
	NextTarget: () -> AttackPanelCoordinator.Target?,
	PreviousTarget: () -> AttackPanelCoordinator.Target?,
	RefreshTargets: () -> AttackPanelCoordinator.Target?,
	SubmitWorldPoint: (Vector3) -> AttackPanelCoordinator.RequestResult,
	Cancel: () -> (),
	RestoreCamera: () -> boolean,
	GetCurrentTarget: () -> AttackPanelCoordinator.Target?,
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

	local query = MonsterAttackRemoteClient.QueryTargets()
	if not query.Succeeded then
		callbacks.OnUnavailable(query.Reason or "TargetQueryFailed")
		return nil
	end
	local targetCache = mapTargets(query.Targets)
	if #targetCache == 0 then
		callbacks.OnUnavailable("TargetUnavailable")
		return nil
	end

	local browseSession = nil
	local followSession = nil
	local inputSession = nil
	local panelSession = nil
	local crosshairSession = nil

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
		})
		if not crosshairSession then
			warn("攻击准星启动失败：" .. tostring(crosshairReason))
		end
	else
		warn("找不到攻击准星模板：ReplicatedStorage/" .. crosshairConfig.TemplateName)
	end

	panelSession = AttackPanelCoordinator.Open(spawnPointId, {
		LocalPlayer = Players.LocalPlayer,
		GetTargets = function()
			return targetCache
		end,
		RequestAttack = MonsterAttackRemoteClient.RequestAttack,
		OnTargetChanged = function(target)
			if crosshairSession then
				crosshairSession.SetTerritories(target.UnlockedTerritories)
			end
			if browseSession then
				browseSession.SetTarget(target.AttackView)
			else
				browseSession = AttackBrowseCamera.Open(
					target.AttackView,
					MonsterAttackSelectionConfig.BrowseCamera
				)
			end
			if callbacks.OnTargetChanged then
				callbacks.OnTargetChanged(target)
			end
		end,
		OnTargetUnavailable = function()
			if crosshairSession then
				crosshairSession.SetTerritories({})
			end
			callbacks.OnUnavailable("TargetUnavailable")
		end,
		OnValidationFailed = function(reason)
			if callbacks.OnValidationFailed then
				callbacks.OnValidationFailed(reason)
			end
		end,
		OnAccepted = function(result, _target)
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
		end,
		OnClosed = function(reason)
			stopInput()
			stopCrosshair()
			restoreBrowseCamera()
			if reason == "Cancelled" then
				callbacks.OnCancelled()
			end
			if callbacks.OnClosed then
				callbacks.OnClosed(reason)
			end
		end,
	})

	inputSession = WorldPointInputController.Start(function(worldPoint)
		if panelSession and panelSession.IsOpen() then
			panelSession.SubmitWorldPoint(worldPoint)
		end
	end)

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
