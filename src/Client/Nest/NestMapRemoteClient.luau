--[[
	职责：把巢穴 Map RemoteFunction 适配成稳定的客户端调用。
	输入：GetState 无参数；Dispatch 接收载具实例 ID 和 NestId；Recall 接收载具实例 ID。
	输出：服务端返回的状态、动作结果和稳定失败原因。
	内部算法：等待唯一 RemoteFunction → pcall InvokeServer → 校验基本响应外形。
	不负责：镜头、按钮状态、巢穴规则或载具战斗。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NestMapProtocol = require(ReplicatedStorage.Shared.Nest.NestMapProtocol)

local NestMapRemoteClient = {}
local remote: RemoteFunction? = nil

local function getRemote(): RemoteFunction
	if remote and remote.Parent then
		return remote
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	local instance = remotes:WaitForChild(NestMapProtocol.RemoteName, 10)
	assert(instance and instance:IsA("RemoteFunction"), "找不到巢穴 Map RemoteFunction")
	remote = instance
	return instance
end

local function request(requestKind: string, value1: string?, value2: string?)
	local succeeded, responseOrError = pcall(function()
		return getRemote():InvokeServer(requestKind, value1, value2)
	end)
	if not succeeded then
		warn(string.format("巢穴 Map Remote 失败：%s (%s)", requestKind, tostring(responseOrError)))
		return { Succeeded = false, Reason = "RequestFailed", State = nil }
	end
	if type(responseOrError) ~= "table" or type(responseOrError.Succeeded) ~= "boolean" then
		return { Succeeded = false, Reason = "InvalidServerResponse", State = nil }
	end
	return responseOrError
end

function NestMapRemoteClient.GetState()
	return request(NestMapProtocol.RequestKinds.GetState, nil, nil)
end

function NestMapRemoteClient.Dispatch(vehicleInstanceId: string, nestId: string)
	return request(NestMapProtocol.RequestKinds.Dispatch, vehicleInstanceId, nestId)
end

function NestMapRemoteClient.Recall(vehicleInstanceId: string)
	return request(NestMapProtocol.RequestKinds.Recall, vehicleInstanceId, nil)
end

return NestMapRemoteClient
