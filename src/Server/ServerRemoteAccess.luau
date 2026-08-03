--[[
	职责：创建或复用 ReplicatedStorage/Remotes 下的服务器 Remote。
	输入：EnsureEvent / EnsureFunction 接收非空 Remote 名称。
	输出：名称唯一且类型正确的 RemoteEvent 或 RemoteFunction。
	内部算法：确保 Remotes Folder 存在，再复用同名实例或创建目标类型。
	不负责：协议名称、网络参数校验、事件绑定或业务处理。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerRemoteAccess = {}

local ROOT_NAME = "Remotes"

local function ensureRoot(): Folder
	local existing = ReplicatedStorage:FindFirstChild(ROOT_NAME)
	if existing then
		assert(existing:IsA("Folder"), "ReplicatedStorage.Remotes 必须是 Folder")
		return existing
	end

	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root.Parent = ReplicatedStorage
	return root
end

local function ensure(name: string, className: "RemoteEvent" | "RemoteFunction"): Instance
	assert(type(name) == "string" and name ~= "", "Remote 名称必须是非空字符串")
	local root = ensureRoot()
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA(className), string.format("%s 必须是 %s", name, className))
		return existing
	end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = root
	return remote
end

function ServerRemoteAccess.EnsureEvent(name: string): RemoteEvent
	return ensure(name, "RemoteEvent") :: RemoteEvent
end

function ServerRemoteAccess.EnsureFunction(name: string): RemoteFunction
	return ensure(name, "RemoteFunction") :: RemoteFunction
end

return table.freeze(ServerRemoteAccess)
