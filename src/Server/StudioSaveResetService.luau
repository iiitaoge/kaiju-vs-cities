--[[
	职责：提供仅 Studio 可见的一键删档 Remote 边界。
	输入：Start 无参数；RemoteFunction 调用者只能删除自己的开发存档。
	输出：Succeeded、Reason、Detail。
	内部算法：Studio 门禁 → 创建测试 Remote → 委托 PlayerPersistenceCoordinator。
	不负责：DataStore Key、保存队列、UI 或正式服删档。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlayerPersistenceCoordinator = require(script.Parent.PlayerPersistenceCoordinator)

local StudioSaveResetService = {}

local REMOTE_NAME = "StudioSaveReset"
local started = false

local function ensureRemote(): RemoteFunction
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	assert(remotes and remotes:IsA("Folder"), "ReplicatedStorage/Remotes 必须是 Folder")
	local existing = remotes:FindFirstChild(REMOTE_NAME)
	if existing then
		assert(existing:IsA("RemoteFunction"), existing:GetFullName() .. " 必须是 RemoteFunction")
		return existing
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = REMOTE_NAME
	remote.Parent = remotes
	return remote
end

function StudioSaveResetService.Start()
	if started or not RunService:IsStudio() then
		return
	end
	started = true
	local remote = ensureRemote()
	remote.OnServerInvoke = function(player)
		return PlayerPersistenceCoordinator.DeleteStudioSave(player)
	end
end

return StudioSaveResetService
