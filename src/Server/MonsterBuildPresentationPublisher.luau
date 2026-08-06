--[[
	职责：广播培养罐/怪兽建造表现，并按明确阶段等待服务器业务时间线。
	输入：Publish 接收协议命令；Wait 接收持续时间和可选取消检查；PublishAndWait 组合两者。
	输出：广播或等待是否完成及稳定失败原因。
	内部算法：命令验证与 FireAllClients、Heartbeat 时长等待彼此独立，可由上层在阶段边界恢复权威模型。
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

function MonsterBuildPresentationPublisher.Publish(
	command: MonsterBuildPresentationProtocol.Command
): Result
	local valid, reason = MonsterBuildPresentationProtocol.Validate(command)
	if not valid then
		return { Succeeded = false, Reason = reason or "InvalidPresentationCommand" }
	end
	local published, publishError = pcall(function()
		getRemote():FireAllClients(command)
	end)
	if not published then
		warn("广播怪兽建造表现失败：", publishError)
		return { Succeeded = false, Reason = "PresentationPublishFailed" }
	end
	return { Succeeded = true, Reason = nil }
end

function MonsterBuildPresentationPublisher.Wait(
	duration: number,
	isCancelled: (() -> boolean)?
): Result
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

function MonsterBuildPresentationPublisher.PublishAndWait(
	command: MonsterBuildPresentationProtocol.Command,
	duration: number,
	isCancelled: (() -> boolean)?
): Result
	local published = MonsterBuildPresentationPublisher.Publish(command)
	if not published.Succeeded then
		return published
	end
	return MonsterBuildPresentationPublisher.Wait(duration, isCancelled)
end

return MonsterBuildPresentationPublisher
