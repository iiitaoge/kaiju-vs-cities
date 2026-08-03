--[[
	职责：在客户端按玩家 Plot 场景合同查找一个实体按钮。

	输入：OwnerUserId、ZoneId、ButtonName、等待时长。
	输出：Plot/Zones/<ZoneId>/Buttons/<ButtonName> 下的 Model，超时返回 nil。
	内部算法：委托 LocalPlayerPlotAccess 定位 Plot，再走按钮固定子路径。

	不负责：按钮状态、业务请求或触碰监听。
]]

local LocalPlayerPlotAccess = require(script.Parent.Parent.LocalPlayerPlotAccess)

local LocalPlotButtonAccess = {}

function LocalPlotButtonAccess.FindInPlot(
	plot: Model,
	zoneId: string,
	buttonName: string
): Model?
	local zones = plot:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(zoneId)
	local buttons = zone and zone:FindFirstChild("Buttons")
	local button = buttons and buttons:FindFirstChild(buttonName)
	return if button and button:IsA("Model") then button else nil
end

function LocalPlotButtonAccess.WaitForPlot(
	ownerUserId: number,
	timeout: number
): Model?
	return LocalPlayerPlotAccess.Wait(ownerUserId, timeout)
end

function LocalPlotButtonAccess.WaitFor(
	ownerUserId: number,
	zoneId: string,
	buttonName: string,
	timeout: number
): Model?
	local deadline = os.clock() + timeout
	repeat
		local plot = LocalPlayerPlotAccess.Find(ownerUserId)
		local button = plot and LocalPlotButtonAccess.FindInPlot(plot, zoneId, buttonName)
		if button then
			return button
		end
		task.wait()
	until os.clock() >= deadline
	local plot = LocalPlayerPlotAccess.Find(ownerUserId)
	return if plot then LocalPlotButtonAccess.FindInPlot(plot, zoneId, buttonName) else nil
end

return LocalPlotButtonAccess
