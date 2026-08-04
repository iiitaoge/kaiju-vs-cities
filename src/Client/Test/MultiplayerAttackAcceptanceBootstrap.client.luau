--[[
	职责：仅在指定的 Studio 脚本化多人测试中启动本地攻击验收驱动。
	输入：StudioTestService 的 TestArgument，以及服务端创建的验收 RemoteEvent。
	输出：连接正式攻击 Remote，并把查询、攻击和表现证据回传给验收服务端。
	内部算法：等待共享控制通道后复用 MultiplayerAttackAcceptanceClient。
	不负责：准备服务端状态、直接执行攻击算法、改变正式 UI 或在已发布客户端运行。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MultiplayerAttackAcceptanceClient = require(
	script.Parent.MultiplayerAttackAcceptanceClient
)
local MultiplayerAttackAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.MultiplayerAttackAcceptanceProtocol
)

if not RunService:IsStudio() then
	return
end

local StudioTestService = game:GetService("StudioTestService")
if StudioTestService:GetTestArgs() ~= MultiplayerAttackAcceptanceProtocol.TestArgument then
	return
end

local REMOTE_WAIT_TIMEOUT_SECONDS = 30
local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT_TIMEOUT_SECONDS)
assert(remotes and remotes:IsA("Folder"), "多人攻击验收找不到 ReplicatedStorage.Remotes")

local control = remotes:WaitForChild(
	MultiplayerAttackAcceptanceProtocol.RemoteName,
	REMOTE_WAIT_TIMEOUT_SECONDS
)
assert(control and control:IsA("RemoteEvent"), "多人攻击验收控制通道不存在或类型错误")

MultiplayerAttackAcceptanceClient.Run(control)
