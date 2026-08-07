--[[
	职责：按服务器给出的目标 OwnerUserId 或 PlotName 与 RegionId 查找客户端可见的 CameraMarker。
	输入：目标玩家或 Plot、区域 ID、Marker 名称和等待时长。
	输出：目标 Plot/Zones/<RegionId>/<MarkerName> 的 BasePart，或稳定失败原因。
	不负责：创建/移动 Marker、判断攻击合法性、控制 CurrentCamera 或修改怪兽。
]]

local LocalPlayerPlotAccess = require(script.Parent.Parent.LocalPlayerPlotAccess)

local LocalMonsterAttackCameraMarkerAccess = {}

local function waitMarker(
	getPlot: () -> Model?,
	regionId: string,
	markerName: string,
	timeout: number
): (BasePart?, string?)
	local deadline = os.clock() + timeout
	local lastReason = "TargetPlotUnavailable"
	repeat
		local plot = getPlot()
		if plot then
			local zones = plot:FindFirstChild("Zones")
			if not zones then
				lastReason = "TargetZonesUnavailable"
			else
				local region = zones:FindFirstChild(regionId)
				if not region then
					lastReason = "TargetRegionUnavailable"
				else
					local marker = region:FindFirstChild(markerName)
					if marker then
						if marker:IsA("BasePart") then
							return marker, nil
						end
						return nil, "CameraMarkerMustBeBasePart"
					end
					lastReason = "CameraMarkerUnavailable"
				end
			end
		end
		if os.clock() >= deadline then
			break
		end
		task.wait()
	until false
	return nil, lastReason
end

function LocalMonsterAttackCameraMarkerAccess.Wait(
	targetOwnerUserId: number,
	regionId: string,
	markerName: string,
	timeout: number
): (BasePart?, string?)
	if type(targetOwnerUserId) ~= "number" or targetOwnerUserId == 0 then
		return nil, "InvalidTargetOwnerUserId"
	end
	if type(regionId) ~= "string" or regionId == "" then
		return nil, "InvalidRegionId"
	end
	if type(markerName) ~= "string" or markerName == "" then
		return nil, "InvalidMarkerName"
	end
	if type(timeout) ~= "number" or timeout < 0 then
		return nil, "InvalidTimeout"
	end

	return waitMarker(
		function()
			return LocalPlayerPlotAccess.Find(targetOwnerUserId)
		end,
		regionId,
		markerName,
		timeout
	)
end

function LocalMonsterAttackCameraMarkerAccess.WaitByPlotName(
	plotName: string,
	regionId: string,
	markerName: string,
	timeout: number
): (BasePart?, string?)
	if type(plotName) ~= "string" or plotName == "" then
		return nil, "InvalidTargetPlotName"
	end
	if type(regionId) ~= "string" or regionId == "" then
		return nil, "InvalidRegionId"
	end
	if type(markerName) ~= "string" or markerName == "" then
		return nil, "InvalidMarkerName"
	end
	if type(timeout) ~= "number" or timeout < 0 then
		return nil, "InvalidTimeout"
	end

	return waitMarker(
		function()
			local root = workspace:FindFirstChild("PlayerPlots")
			local plot = root and root:FindFirstChild(plotName)
			return if plot and plot:IsA("Model") then plot else nil
		end,
		regionId,
		markerName,
		timeout
	)
end

return LocalMonsterAttackCameraMarkerAccess
