--[[
	职责：把载具管理 RemoteFunction 适配成稳定的客户端调用。
	输入：GetState 无参数；Upgrade/Destroy 接收车辆实例 ID。
	输出：服务端返回的 Succeeded、Reason、State 和奖励/余额字段。
	内部算法：等待唯一 RemoteFunction → 保护 InvokeServer → 校验基本响应外形。
	不负责：UI、按钮状态、等级配置或货币计算。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleManagementProtocol = require(
	ReplicatedStorage.Shared.Vehicle.VehicleManagementProtocol
)

local VehicleManagementRemoteClient = {}
local remote: RemoteFunction? = nil

local function getRemote(): RemoteFunction
	if remote and remote.Parent then
		return remote
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	local instance = remotes:WaitForChild(VehicleManagementProtocol.RemoteName, 10)
	assert(
		instance and instance:IsA("RemoteFunction"),
		"找不到载具管理 RemoteFunction"
	)
	remote = instance
	return instance
end

local function request(requestKind: string, instanceId: string?)
	local succeeded, responseOrError = pcall(function()
		return getRemote():InvokeServer(requestKind, instanceId)
	end)
	if not succeeded then
		warn(string.format("载具管理 Remote 失败：%s (%s)", requestKind, tostring(responseOrError)))
		return { Succeeded = false, Reason = "RequestFailed", State = nil }
	end
	if type(responseOrError) ~= "table" or type(responseOrError.Succeeded) ~= "boolean" then
		return { Succeeded = false, Reason = "InvalidServerResponse", State = nil }
	end
	return responseOrError
end

function VehicleManagementRemoteClient.GetState()
	return request(VehicleManagementProtocol.RequestKinds.GetState, nil)
end

function VehicleManagementRemoteClient.Upgrade(instanceId: string)
	return request(VehicleManagementProtocol.RequestKinds.Upgrade, instanceId)
end

function VehicleManagementRemoteClient.Destroy(instanceId: string)
	return request(VehicleManagementProtocol.RequestKinds.Destroy, instanceId)
end

return VehicleManagementRemoteClient
