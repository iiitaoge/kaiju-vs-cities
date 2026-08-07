--[[
	职责：向当前玩家发布区域扩展和怪兽培养罐建造完成提示。
	输入：在线 Player、RegionId 或 SpawnPointId。
	输出：Remote 发布结果；失败不影响已提交的业务事务。
	内部算法：构造协议 command → 校验 → FireClient。
	不负责：区域/培养罐业务状态、英文文案、UI 显示或计时。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExpandedPresentationProtocol = require(
	ReplicatedStorage.Shared.UI.ExpandedPresentationProtocol
)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)

local ExpandedPresentationPublisher = {}

export type Result = {
	Succeeded: boolean,
	Reason: string?,
}

local remote: RemoteEvent? = nil

local function result(succeeded: boolean, reason: string?): Result
	return {
		Succeeded = succeeded,
		Reason = reason,
	}
end

local function getRemote(): RemoteEvent
	if remote and remote.Parent then
		return remote
	end
	remote = ServerRemoteAccess.EnsureEvent(ExpandedPresentationProtocol.RemoteName)
	return remote
end

function ExpandedPresentationPublisher.Start()
	getRemote()
end

local function publish(player: Player, command: ExpandedPresentationProtocol.Command): Result
	if typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or player.Parent ~= Players
	then
		return result(false, "PlayerUnavailable")
	end
	local valid, reason = ExpandedPresentationProtocol.Validate(command)
	if not valid then
		return result(false, reason or "InvalidCommand")
	end
	local published, publishError = pcall(function()
		getRemote():FireClient(player, command)
	end)
	if not published then
		warn("发布区域扩展提示失败：", publishError)
		return result(false, "PresentationPublishFailed")
	end
	return result(true, nil)
end

function ExpandedPresentationPublisher.PublishRegionExpanded(
	player: Player,
	regionId: string
): Result
	return publish(player, {
		Kind = ExpandedPresentationProtocol.Kinds.RegionExpanded,
		RegionId = regionId,
	})
end

function ExpandedPresentationPublisher.PublishIncubatorBuilt(
	player: Player,
	spawnPointId: string
): Result
	return publish(player, {
		Kind = ExpandedPresentationProtocol.Kinds.IncubatorBuilt,
		SpawnPointId = spawnPointId,
	})
end

return ExpandedPresentationPublisher
