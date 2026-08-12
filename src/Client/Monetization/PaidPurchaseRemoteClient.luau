--[[
	职责：提供付费购买准备请求和收据结果事件的客户端薄适配层。
	输入：指定 SpawnPointId；输出：服务端返回的商品准备结果或已发放事件。
	不负责：商品价格、购买弹窗、收据发放或 UI 文案。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaidPurchaseProtocol = require(ReplicatedStorage.Shared.Monetization.PaidPurchaseProtocol)

local PaidPurchaseRemoteClient = {}

local function getRemotes(): Folder
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "ReplicatedStorage.Remotes 不可用")
	return remotes
end

function PaidPurchaseRemoteClient.PrepareMonsterUpgrade(spawnPointId: string)
	local remote = getRemotes():WaitForChild(PaidPurchaseProtocol.RequestRemoteName, 10)
	assert(remote and remote:IsA("RemoteFunction"), "付费购买请求 Remote 不可用")
	local succeeded, response = pcall(function()
		return remote:InvokeServer(
			PaidPurchaseProtocol.RequestKinds.PrepareMonsterUpgrade,
			spawnPointId
		)
	end)
	if not succeeded or type(response) ~= "table" then
		return { Succeeded = false, Reason = "RequestFailed", ProductId = 0 }
	end
	return response
end

function PaidPurchaseRemoteClient.CancelMonsterUpgrade(
	spawnPointId: string,
	productId: number
)
	local remote = getRemotes():WaitForChild(PaidPurchaseProtocol.RequestRemoteName, 10)
	assert(remote and remote:IsA("RemoteFunction"), "付费购买请求 Remote 不可用")
	local succeeded, response = pcall(function()
		return remote:InvokeServer(
			PaidPurchaseProtocol.RequestKinds.CancelMonsterUpgrade,
			spawnPointId,
			productId
		)
	end)
	if not succeeded or type(response) ~= "table" then
		return { Succeeded = false, Reason = "RequestFailed", ProductId = 0 }
	end
	return response
end

function PaidPurchaseRemoteClient.GetResultEvent(): RemoteEvent
	local remote = getRemotes():WaitForChild(PaidPurchaseProtocol.ResultRemoteName, 10)
	assert(remote and remote:IsA("RemoteEvent"), "付费购买结果 Remote 不可用")
	return remote
end

return table.freeze(PaidPurchaseRemoteClient)
