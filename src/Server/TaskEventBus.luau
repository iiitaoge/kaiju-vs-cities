--[[
	职责：在服务器内部传递已经确认成功的业务事实。
	输入：Publish 接收 player 和事实表；Connect 接收一个监听函数。
	输出：监听函数收到同一 player 和事实；Publish 不改变业务状态。
	内部算法：使用服务器内存中的监听表同步调用任务处理器，避免业务成功点之后出现一帧延迟。
	不负责：校验客户端请求、计算任务进度、奖励发放或存档。
]]

local TaskEventBus = {}
local listeners: { [number]: (Player, any) -> () } = {}
local nextListenerId = 0

function TaskEventBus.Connect(callback)
	assert(type(callback) == "function", "callback 必须是 function")
	nextListenerId += 1
	local listenerId = nextListenerId
	listeners[listenerId] = callback
	local connected = true
	return {
		Disconnect = function()
			if connected then
				connected = false
				listeners[listenerId] = nil
			end
		end,
	}
end

function TaskEventBus.Publish(player: Player, event)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(event) == "table", "event 必须是 table")
	for listenerId = 1, nextListenerId do
		local callback = listeners[listenerId]
		if callback then
			callback(player, event)
		end
	end
end

return table.freeze(TaskEventBus)
