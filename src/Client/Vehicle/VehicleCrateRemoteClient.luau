--[[
	职责：把载具箱子 RemoteFunction 适配成稳定的客户端调用。
	输入：GetState 无参数；PurchaseDiamond 接收 crateId 和抽取次数 1/5。
	输出：服务端返回的箱子状态、购买结果和余额。
	内部算法：等待唯一 RemoteFunction → 保护 InvokeServer → 校验基本响应外形。
	不负责：按钮、概率计算、货币判断、随机或存档。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleCrateProtocol = require(
	ReplicatedStorage.Shared.Vehicle.VehicleCrateProtocol
)

local VehicleCrateRemoteClient = {}
local remote: RemoteFunction? = nil

local function getRemote(): RemoteFunction
	if remote and remote.Parent then
		return remote
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	local instance = remotes:WaitForChild(VehicleCrateProtocol.RemoteName, 10)
	assert(
		instance and instance:IsA("RemoteFunction"),
		"找不到载具箱子 RemoteFunction"
	)
	remote = instance
	return instance
end

local function request(requestKind: string, crateId: string?, drawCount: number?)
	local succeeded, responseOrError = pcall(function()
		return getRemote():InvokeServer(requestKind, crateId, drawCount)
	end)
	if not succeeded then
		warn(string.format("载具箱子 Remote 失败：%s (%s)", requestKind, tostring(responseOrError)))
		return { Succeeded = false, Reason = "RequestFailed", State = nil }
	end
	if type(responseOrError) ~= "table" or type(responseOrError.Succeeded) ~= "boolean" then
		return { Succeeded = false, Reason = "InvalidServerResponse", State = nil }
	end
	return responseOrError
end

function VehicleCrateRemoteClient.GetState()
	return request(VehicleCrateProtocol.RequestKinds.GetState, nil, nil)
end

function VehicleCrateRemoteClient.PurchaseDiamond(crateId: string, drawCount: number)
	return request(
		VehicleCrateProtocol.RequestKinds.PurchaseDiamond,
		crateId,
		drawCount
	)
end

return VehicleCrateRemoteClient
