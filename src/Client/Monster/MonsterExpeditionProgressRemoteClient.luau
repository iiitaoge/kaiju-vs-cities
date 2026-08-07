--[[
	职责：接收并校验服务器发给防守方的出征进度通知，并补查当前状态。
	输入：Observe 接收本地处理回调。
	输出：实时事件或状态查询返回的合法 ExpeditionStarted/ExpeditionEnded command。
	不负责：计算剩余时间、修改进度条或控制防守方决斗观看按钮。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterExpeditionProgressProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionProgressProtocol
)

local MonsterExpeditionProgressRemoteClient = {}

local function getRemote(): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	local remote = remotes:WaitForChild(MonsterExpeditionProgressProtocol.RemoteName, 10)
	assert(
		remote and remote:IsA("RemoteEvent"),
		"找不到防守方出征进度 RemoteEvent："
			.. MonsterExpeditionProgressProtocol.RemoteName
	)
	return remote
end

local function getQueryRemote(): RemoteFunction
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(remotes and remotes:IsA("Folder"), "找不到 ReplicatedStorage/Remotes")
	local remote = remotes:WaitForChild(MonsterExpeditionProgressProtocol.QueryRemoteName, 10)
	assert(
		remote and remote:IsA("RemoteFunction"),
		"找不到防守方出征进度查询 RemoteFunction："
			.. MonsterExpeditionProgressProtocol.QueryRemoteName
	)
	return remote
end

local function deliver(
	listener: (MonsterExpeditionProgressProtocol.Command) -> (),
	command
)
	local valid, reason = MonsterExpeditionProgressProtocol.Validate(command)
	if not valid then
		warn("拒绝防守方出征进度命令：", reason)
		return
	end
	listener(command)
end

function MonsterExpeditionProgressRemoteClient.Observe(
	listener: (MonsterExpeditionProgressProtocol.Command) -> ()
): RBXScriptConnection
	assert(type(listener) == "function", "listener 必须是 function")
	local connection = getRemote().OnClientEvent:Connect(function(command)
		deliver(listener, command)
	end)
	task.spawn(function()
		local succeeded, responseOrError = pcall(function()
			return getQueryRemote():InvokeServer()
		end)
		if not succeeded then
			warn("查询防守方出征进度失败：", responseOrError)
			return
		end
		if type(responseOrError) ~= "table"
			or responseOrError.Succeeded ~= true
		then
			warn("防守方出征进度查询返回无效结果")
			return
		end
		if responseOrError.Command ~= nil then
			deliver(listener, responseOrError.Command)
		end
	end)
	return connection
end

return MonsterExpeditionProgressRemoteClient
