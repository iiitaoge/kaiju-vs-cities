--[[
	职责：把 TutorialSnapshot RemoteFunction 适配到服务器权威引导查询。
	输入：本地玩家发起的无参数查询。
	输出：稳定的成功快照，或 Succeeded=false 与 Reason。
	内部算法：先检查存档 Ready，再保护调用 TutorialSnapshotQuery。
	不负责：轮询、UI、Beam、步骤计算或完成写入。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)
local TutorialSnapshotQuery = require(script.Parent.TutorialSnapshotQuery)
local TutorialProtocol = require(ReplicatedStorage.Shared.Tutorial.TutorialProtocol)

local remote = ServerRemoteAccess.EnsureFunction(TutorialProtocol.SnapshotRemoteName)

remote.OnServerInvoke = function(player)
	if PlayerDataReadyService.Get(player).Status ~= "Ready" then
		return { Succeeded = false, Reason = "PlayerDataNotReady" }
	end
	local succeeded, responseOrError = xpcall(function()
		return TutorialSnapshotQuery.Query(player)
	end, debug.traceback)
	if not succeeded then
		warn(string.format("查询新手引导异常：%s (%s)", player.Name, tostring(responseOrError)))
		return { Succeeded = false, Reason = "ServerError" }
	end
	return responseOrError
end
