--[[
	职责：广播一次培养罐/怪兽建造表现，并等待服务器业务阶段结束。
	输入：协议命令、持续时间、可选取消检查。
	输出：表现等待是否完成及稳定失败原因。
	内部算法：验证命令 → FireAllClients → Heartbeat 等待配置时长并轮询取消。
	不负责：创建/隐藏模型、选择模板、播放动画或提交购买状态。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MonsterBuildPresentationProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterBuildPresentationProtocol
)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)

local MonsterBuildPresentationPublisher = {}

export type Result = {
	Succeeded: boolean,
	Reason: string?,
}

local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if remote and remote.Parent then
		return remote
	end
	remote = ServerRemoteAccess.EnsureEvent(MonsterBuildPresentationProtocol.RemoteName)
	return remote
end

function MonsterBuildPresentationPublisher.Start()
	getRemote()
end

function MonsterBuildPresentationPublisher.PublishAndWait(
	command: MonsterBuildPresentationProtocol.Command,
	duration: number,
	isCancelled: (() -> boolean)?
): Result
	local valid, reason = MonsterBuildPresentationProtocol.Validate(command)
	if not valid then
		return { Succeeded = false, Reason = reason or "InvalidPresentationCommand" }
	end
	if type(duration) ~= "number"
		or duration ~= duration
		or duration == math.huge
		or duration <= 0
	then
		return { Succeeded = false, Reason = "InvalidPresentationDuration" }
	end
	if isCancelled ~= nil and type(isCancelled) ~= "function" then
		return { Succeeded = false, Reason = "InvalidCancellationCheck" }
	end

	local published, publishError = pcall(function()
		getRemote():FireAllClients(command)
	end)
	if not published then
		warn("广播怪兽建造表现失败：", publishError)
		return { Succeeded = false, Reason = "PresentationPublishFailed" }
	end

	local deadline = os.clock() + duration
	repeat
		if isCancelled then
			local checked, cancelled = pcall(isCancelled)
			if not checked then
				return { Succeeded = false, Reason = "CancellationCheckFailed" }
			end
			if cancelled then
				return { Succeeded = false, Reason = "Cancelled" }
			end
		end
		RunService.Heartbeat:Wait()
	until os.clock() >= deadline
	return { Succeeded = true, Reason = nil }
end

return MonsterBuildPresentationPublisher
