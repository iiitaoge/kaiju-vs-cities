--[[
	职责：把单个界面的业务显隐意图与全局界面模式许可组合起来。
	输入：显示通道、应用最终显隐的回调，以及可选初始业务显隐值。
	输出：可更新业务显隐并销毁的门控句柄。
	内部算法：每次业务状态或模式变化时应用 DesiredVisible AND ChannelAllowed。
	不负责：拥有 GUI、推断业务状态、切换全局模式或保存 Instance 快照。
]]

local LocalUIModeService = require(script.Parent.LocalUIModeService)

local LocalUIVisibilityGate = {}

export type Handle = {
	SetDesiredVisible: (self: Handle, boolean) -> (),
	Refresh: (self: Handle) -> (),
	Destroy: (self: Handle) -> (),
}

function LocalUIVisibilityGate.Create(
	channel: string,
	applyVisibility: (boolean) -> (),
	initialDesiredVisible: boolean?
): Handle
	assert(type(channel) == "string" and channel ~= "", "channel 必须是非空字符串")
	assert(type(applyVisibility) == "function", "applyVisibility 必须是 function")

	local desiredVisible = initialDesiredVisible == true
	local destroyed = false
	local subscription = nil
	local handle = {} :: any

	local function apply()
		if destroyed then
			return
		end
		applyVisibility(
			desiredVisible and LocalUIModeService.IsAllowed(channel)
		)
	end

	function handle:SetDesiredVisible(nextVisible: boolean)
		assert(type(nextVisible) == "boolean", "nextVisible 必须是 boolean")
		desiredVisible = nextVisible
		apply()
	end

	function handle:Refresh()
		apply()
	end

	function handle:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		if subscription then
			subscription:Disconnect()
			subscription = nil
		end
	end

	subscription = LocalUIModeService.Observe(function()
		apply()
	end)
	return handle
end

return LocalUIVisibilityGate
