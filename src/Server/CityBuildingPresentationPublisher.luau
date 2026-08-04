--[[
	职责：把一次已提交的城市建筑变化广播给所有在线客户端。
	输入：通过纯协议验证的 RegionUpgrade 或 HouseLifecycle Command。
	输出：通过 ReplicatedStorage/Remotes/CityBuildingPresentation FireAllClients；无业务返回值。
	内部算法：通过 ServerRemoteAccess 获取并缓存唯一 RemoteEvent，发送前验证命令基本结构。
	不负责：不修改玩家状态、不刷新建筑、不等待动画完成。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CityBuildingPresentationProtocol = require(
	ReplicatedStorage.Shared.Building.CityBuildingPresentationProtocol
)
local ServerRemoteAccess = require(script.Parent.ServerRemoteAccess)

local CityBuildingPresentationPublisher = {}

export type RegionUpgradeCommand = {
	Kind: "RegionUpgrade",
	OwnerUserId: number,
	RegionId: string,
	PreviousLevel: number,
	NewLevel: number,
	PresentationId: string,
	BuildSpeedMultiplier: number,
	HouseIds: { string },
}

export type HouseLifecycleCommand = {
	Kind: "HouseDestroyed" | "HouseRebuilding",
	OwnerUserId: number,
	RegionId: string,
	HouseId: string,
	Level: number,
	PresentationId: string,
	BuildSpeedMultiplier: number,
}

export type Command = RegionUpgradeCommand | HouseLifecycleCommand

local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if remote and remote.Parent then
		return remote
	end
	remote = ServerRemoteAccess.EnsureEvent(CityBuildingPresentationProtocol.RemoteName)
	return remote
end

function CityBuildingPresentationPublisher.Start()
	getRemote()
end

function CityBuildingPresentationPublisher.Publish(command: Command)
	local valid, reason = CityBuildingPresentationProtocol.Validate(command)
	assert(valid, "无效城市建筑表现命令：" .. (reason or "Unknown"))
	getRemote():FireAllClients(command)
end

return CityBuildingPresentationPublisher
