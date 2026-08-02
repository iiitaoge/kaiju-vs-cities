--[[
	职责：
	- 在客户端按稳定身份查找玩家 Plot、Slot 和服务器权威建筑。

	输入：
	- OwnerUserId、RegionId、SlotId 或 HouseId，以及可选等待时长。

	输出：
	- 对应的 Plot、Slot BasePart 或建筑 Model；找不到时返回 nil。

	内部算法：
	- 只遍历 Workspace/PlayerPlots，并验证 OwnerUserId Attribute 和正式数据树路径。

	不负责：
	- 不读取玩家状态、不解析模板、不修改 Instance。
]]

local LocalPlayerCityRuntimeAccess = {}

local function isOwnerUserId(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value > -math.huge
		and value % 1 == 0
		and value ~= 0
end

function LocalPlayerCityRuntimeAccess.FindPlot(ownerUserId: number): Model?
	if not isOwnerUserId(ownerUserId) then
		return nil
	end

	local root = workspace:FindFirstChild("PlayerPlots")
	if not root or not root:IsA("Folder") then
		return nil
	end
	for _, child in root:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OwnerUserId") == ownerUserId then
			return child
		end
	end
	return nil
end

function LocalPlayerCityRuntimeAccess.WaitForPlot(
	ownerUserId: number,
	timeout: number
): Model?
	assert(type(timeout) == "number" and timeout >= 0, "timeout 必须是非负数")
	local deadline = os.clock() + timeout
	repeat
		local plot = LocalPlayerCityRuntimeAccess.FindPlot(ownerUserId)
		if plot then
			return plot
		end
		task.wait()
	until os.clock() >= deadline
	return LocalPlayerCityRuntimeAccess.FindPlot(ownerUserId)
end

function LocalPlayerCityRuntimeAccess.FindSlot(
	plot: Model,
	regionId: string,
	slotId: string
): BasePart?
	if not plot:IsA("Model") or type(regionId) ~= "string" or type(slotId) ~= "string" then
		return nil
	end
	local zones = plot:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(regionId)
	local slots = zone and zone:FindFirstChild("Slots")
	local slot = slots and slots:FindFirstChild(slotId)
	return if slot and slot:IsA("BasePart") then slot else nil
end

function LocalPlayerCityRuntimeAccess.FindBuilding(plot: Model, houseId: string): Model?
	if not plot:IsA("Model") or type(houseId) ~= "string" then
		return nil
	end
	local runtime = plot:FindFirstChild("Runtime")
	local buildings = runtime and runtime:FindFirstChild("Buildings")
	local model = buildings and buildings:FindFirstChild(houseId)
	if not model or not model:IsA("Model") then
		return nil
	end
	if model:GetAttribute("BuildingHouseId") ~= houseId then
		return nil
	end
	return model
end

function LocalPlayerCityRuntimeAccess.WaitForBuilding(
	plot: Model,
	houseId: string,
	timeout: number
): Model?
	assert(type(timeout) == "number" and timeout >= 0, "timeout 必须是非负数")
	local deadline = os.clock() + timeout
	repeat
		local model = LocalPlayerCityRuntimeAccess.FindBuilding(plot, houseId)
		if model then
			return model
		end
		task.wait()
	until os.clock() >= deadline
	return LocalPlayerCityRuntimeAccess.FindBuilding(plot, houseId)
end

return LocalPlayerCityRuntimeAccess
