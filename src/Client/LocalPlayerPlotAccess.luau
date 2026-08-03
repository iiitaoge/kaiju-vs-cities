--[[
	职责：在客户端按服务器权威 OwnerUserId 查找玩家 Plot。
	输入：非零整数 OwnerUserId；Wait 额外接收非负超时秒数。
	输出：Workspace/PlayerPlots 下匹配的 Model，未找到或超时时返回 nil。
	内部算法：只遍历 PlayerPlots 的直接子级并比较 OwnerUserId Attribute。
	不负责：Zone、按钮、建筑、怪兽路径或任何 Instance 修改。
]]

local LocalPlayerPlotAccess = {}

local function isOwnerUserId(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value > -math.huge
		and value % 1 == 0
		and value ~= 0
end

function LocalPlayerPlotAccess.Find(ownerUserId: number): Model?
	if not isOwnerUserId(ownerUserId) then
		return nil
	end

	local root = workspace:FindFirstChild("PlayerPlots")
	if not root or not root:IsA("Folder") then
		return nil
	end
	for _, plot in root:GetChildren() do
		if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == ownerUserId then
			return plot
		end
	end
	return nil
end

function LocalPlayerPlotAccess.Wait(ownerUserId: number, timeout: number): Model?
	assert(type(timeout) == "number" and timeout >= 0, "timeout 必须是非负数")
	local deadline = os.clock() + timeout
	repeat
		local plot = LocalPlayerPlotAccess.Find(ownerUserId)
		if plot then
			return plot
		end
		task.wait()
	until os.clock() >= deadline
	return LocalPlayerPlotAccess.Find(ownerUserId)
end

return LocalPlayerPlotAccess
