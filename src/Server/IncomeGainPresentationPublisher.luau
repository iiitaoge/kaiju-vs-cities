--[[
	职责：只向收入所属玩家发布一次已提交的房屋收入表现。
	输入：在线 Player、通过协议验证的 Automatic 或 Touch Command。
	输出：是否成功通过 IncomeGainPresentation RemoteEvent FireClient。
	内部算法：复用唯一 RemoteEvent，发送前执行共享协议验证。
	不负责：计算或发放收入、选择房屋、播放客户端动画或修改余额。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local IncomeGainPresentationProtocol = require(
	ReplicatedStorage.Shared.Economy.IncomeGainPresentationProtocol
)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)

local IncomeGainPresentationPublisher = {}

local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if remote and remote.Parent then
		return remote
	end
	remote = ServerRemoteAccess.EnsureEvent(IncomeGainPresentationProtocol.RemoteName)
	return remote
end

function IncomeGainPresentationPublisher.Start()
	getRemote()
end

function IncomeGainPresentationPublisher.Publish(
	player: Player,
	command: IncomeGainPresentationProtocol.Command
): boolean
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local valid, reason = IncomeGainPresentationProtocol.Validate(command)
	assert(valid, "无效房屋收入表现命令：" .. (reason or "Unknown"))
	if player.Parent ~= Players then
		return false
	end
	local published, publishError = pcall(function()
		getRemote():FireClient(player, command)
	end)
	if not published then
		warn("发布房屋收入表现失败：", publishError)
	end
	return published
end

return IncomeGainPresentationPublisher
