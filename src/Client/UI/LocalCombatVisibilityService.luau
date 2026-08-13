--[[
	职责：持有当前客户端是否处于战斗流程中的显隐状态，并通知订阅者。
	输入：战斗 UI 控制器调用 SetActive；界面控制器调用 Observe/IsActive。
	输出：稳定的战斗状态和可断开的状态监听。
	内部算法：状态变化时快照遍历监听器；监听器异常只记录警告，不阻断其他 UI。
	不负责：判断战斗胜负、计时、修改服务器状态或直接修改 GUI。
]]

local LocalCombatVisibilityService = {}

export type Subscription = {
	Disconnect: (self: Subscription) -> (),
}

local active = false
local listeners: { [any]: (boolean) -> () } = {}

local function publish()
	local snapshot = {}
	for key, listener in listeners do
		table.insert(snapshot, { Key = key, Listener = listener })
	end

	for _, entry in snapshot do
		if listeners[entry.Key] == entry.Listener then
			local succeeded, errorMessage = pcall(entry.Listener, active)
			if not succeeded then
				warn("本地战斗显隐监听器失败：" .. tostring(errorMessage))
			end
		end
	end
end

function LocalCombatVisibilityService.IsActive(): boolean
	return active
end

function LocalCombatVisibilityService.SetActive(nextActive: boolean)
	assert(type(nextActive) == "boolean", "战斗显隐状态必须是 boolean")
	if active == nextActive then
		return
	end
	active = nextActive
	publish()
end

function LocalCombatVisibilityService.Observe(
	listener: (boolean) -> ()
): Subscription
	assert(type(listener) == "function", "战斗显隐监听器必须是 function")

	local key = {}
	listeners[key] = listener
	listener(active)

	local subscription = {} :: any
	function subscription:Disconnect()
		listeners[key] = nil
	end
	return subscription
end

return LocalCombatVisibilityService
