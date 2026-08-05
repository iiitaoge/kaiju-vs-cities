--[[
	职责：提供玩家所属 Plot 重生 UI 的 RemoteFunction 服务入口。
	输入：GetState 或 Execute 请求。
	输出：RebirthCoordinator 的完整状态快照。
	内部算法：检查数据 Ready；Execute 额外验证玩家确实在自己 Plot 的按钮附近。
	不负责：UI、资格公式、存档算法或运行时重建细节。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerJourneyAnalyticsCoordinator = require(
	script.Parent.Analytics.PlayerJourneyAnalyticsCoordinator
)
local RebirthButtonAccess = require(script.Parent.RebirthButtonAccess)
local RebirthCoordinator = require(script.Parent.RebirthCoordinator)
local SecurityAnalyticsAggregator = require(
	script.Parent.Analytics.SecurityAnalyticsAggregator
)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local RebirthProtocol = require(
	ReplicatedStorage.Shared.Progression.RebirthProtocol
)

local RebirthService = {}

local started = false

function RebirthService.Start()
	if started then
		return
	end
	started = true
	RebirthCoordinator.Start()

	local remote = ServerRemoteAccess.EnsureFunction(RebirthProtocol.RemoteName)
	remote.OnServerInvoke = function(player, requestKind)
		local readiness = PlayerDataReadyService.Get(player)
		if readiness.Status ~= "Ready" or not readiness.CanSave then
			return RebirthCoordinator.GetState(player), "PlayerDataNotReady"
		end
		if requestKind == "GetState" then
			local snapshot = RebirthCoordinator.GetState(player)
			PlayerJourneyAnalyticsCoordinator.RecordRebirthState(player, snapshot)
			return snapshot, nil
		end
		if requestKind ~= "Execute" then
			SecurityAnalyticsAggregator.Record(player, "Rebirth", "InvalidRequestKind")
			return RebirthCoordinator.GetState(player), "InvalidRequestKind"
		end

		local nearButton, buttonReason = RebirthButtonAccess.CheckActivation(player)
		if not nearButton then
			SecurityAnalyticsAggregator.Record(player, "Rebirth", "ActivationRejected")
			return RebirthCoordinator.GetState(player), buttonReason
		end
		return RebirthCoordinator.Execute(player), nil
	end
end

return RebirthService
