--[[
	职责：提供仅 Studio 可见的一键删档 Remote 边界。
	输入：Start 无参数；RemoteFunction 调用者只能删除自己的开发存档。
	输出：Succeeded、Reason、Detail。
	内部算法：Studio 门禁 → 获取测试 Remote → 委托 PlayerPersistenceCoordinator。
	不负责：DataStore Key、保存队列、UI 或正式服删档。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StudioSaveResetProtocol = require(
	ReplicatedStorage.Shared.Persistence.StudioSaveResetProtocol
)
local PlayerPersistenceCoordinator = require(script.Parent.PlayerPersistenceCoordinator)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)

local StudioSaveResetService = {}

local started = false

function StudioSaveResetService.Start()
	if started or not RunService:IsStudio() then
		return
	end
	started = true
	local remote = ServerRemoteAccess.EnsureFunction(StudioSaveResetProtocol.RemoteName)
	remote.OnServerInvoke = function(player)
		return PlayerPersistenceCoordinator.DeleteStudioSave(player)
	end
end

return StudioSaveResetService
