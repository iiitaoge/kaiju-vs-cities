--[[
	职责：持有本客户端唯一的独占界面模式会话，并广播模式变化。
	输入：Acquire 接收非 Normal 模式；会话可切换模式或释放；Observe 接收监听器。
	输出：独占会话、当前模式、通道许可和可断开的监听句柄。
	内部算法：同一时刻只允许一个 owner；释放当前 owner 后原子恢复 Normal 并通知所有监听器。
	不负责：查找或修改具体 GUI、决定业务显隐、管理攻击逻辑或 CoreGui。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)

local LocalUIModeService = {}

export type ModeSession = {
	SetMode: (self: ModeSession, string) -> boolean,
	Release: (self: ModeSession) -> boolean,
	IsActive: (self: ModeSession) -> boolean,
}

export type Subscription = {
	Disconnect: (self: Subscription) -> (),
}

local currentMode = UIModeVisibilityRules.Modes.Normal
local currentOwner: any = nil
local listeners: { [any]: (string) -> () } = {}

local function publish()
	local snapshot = {}
	for key, listener in listeners do
		table.insert(snapshot, { Key = key, Listener = listener })
	end
	for _, entry in snapshot do
		if listeners[entry.Key] == entry.Listener then
			local succeeded, errorMessage = pcall(entry.Listener, currentMode)
			if not succeeded then
				warn("本地 UI 模式监听器失败：" .. tostring(errorMessage))
			end
		end
	end
end

function LocalUIModeService.GetMode(): string
	return currentMode
end

function LocalUIModeService.IsAllowed(channel: string): boolean
	return UIModeVisibilityRules.Allows(currentMode, channel)
end

function LocalUIModeService.Acquire(mode: string): (ModeSession?, string?)
	assert(UIModeVisibilityRules.IsMode(mode), "mode 无效")
	assert(mode ~= UIModeVisibilityRules.Modes.Normal, "不能 Acquire Normal 模式")
	if currentOwner then
		return nil, "UIModeBusy"
	end

	local session = {} :: any
	currentOwner = session
	currentMode = mode
	publish()

	function session:SetMode(nextMode: string): boolean
		assert(UIModeVisibilityRules.IsMode(nextMode), "nextMode 无效")
		assert(nextMode ~= UIModeVisibilityRules.Modes.Normal, "请使用 Release 恢复 Normal")
		if currentOwner ~= session then
			return false
		end
		if currentMode ~= nextMode then
			currentMode = nextMode
			publish()
		end
		return true
	end

	function session:Release(): boolean
		if currentOwner ~= session then
			return false
		end
		currentOwner = nil
		currentMode = UIModeVisibilityRules.Modes.Normal
		publish()
		return true
	end

	function session:IsActive(): boolean
		return currentOwner == session
	end

	return session, nil
end

function LocalUIModeService.Observe(listener: (string) -> ()): Subscription
	assert(type(listener) == "function", "listener 必须是 function")
	local key = {}
	listeners[key] = listener
	listener(currentMode)

	local subscription = {} :: any
	function subscription:Disconnect()
		listeners[key] = nil
	end
	return subscription
end

return LocalUIModeService
