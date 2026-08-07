--[[
	职责：读取当前某一块展示空 Plot 的服务器权威单人出征范围。
	输入：无；输出：空 Plot/AttackViewBounds 的 CFrame/Size，或稳定失败原因。
	内部算法：读取 PlayerPlotAssignmentService 维护的一块空 Plot，并验证其 AttackViewBounds。
	不负责：玩家数量、点击校验、相机、怪兽移动、Plot 分配或修改场景。
]]

local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TerritoryPointRules = require(
	ReplicatedStorage.Shared.Monster.TerritoryPointRules
)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local WorkspaceSoloAttackAreaAccess = {}

export type Area = {
	CFrame: CFrame,
	Size: Vector3,
	PlotName: string,
}

local function getPlotByName(plotName: string?): (Model?, string?)
	local root = workspace:FindFirstChild("PlayerPlots")
	if not root or not root:IsA("Folder") then
		return nil, "PlotRootUnavailable"
	end
	if plotName ~= nil and plotName ~= "" then
		local plot = root:FindFirstChild(plotName)
		if plot and plot:IsA("Model") then
			return plot, nil
		end
		return nil, "SoloAttackPlotUnavailable"
	end
	return PlayerPlotAssignmentService.GetDisplayedAvailablePlot()
end

function WorkspaceSoloAttackAreaAccess.Resolve(): (Area?, string?)
	local plot, plotReason = PlayerPlotAssignmentService.GetDisplayedAvailablePlot()
	if not plot then
		return nil, plotReason or "SoloAttackPlotUnavailable"
	end
	local instance = plot:FindFirstChild("AttackViewBounds")
	if not instance or not instance:IsA("BasePart") then
		return nil, "SoloAttackViewUnavailable"
	end
	local size = instance.Size
	if size.X <= 0 or size.Z <= 0 then
		return nil, "InvalidSoloAttackView"
	end
	return {
		CFrame = instance.CFrame,
		Size = size,
		PlotName = plot.Name,
	}, nil
end

-- 输入：命令接受时锁定的展示 Plot 名称，以及单人攻击落点。
-- 输出：展示 Plot 名称与落点所属 R 区域；无法落入具体区域时只返回 Plot 名称。
-- 内部算法：遍历 R1~R6 的 Bounds，复用 TerritoryPointRules 做旋转包围盒判断。
-- 不负责：判断单人攻击合法性、移动怪兽、选择相机参数或发送网络事件。
function WorkspaceSoloAttackAreaAccess.ResolveCameraTarget(
	plotName: string?,
	entryPoint: Vector3
): (string?, string?, string?)
	local plot, plotReason = getPlotByName(plotName)
	if not plot then
		return nil, nil, plotReason or "SoloAttackPlotUnavailable"
	end

	for _, definition in ZoneCatalog.GetAll() do
		if definition.Kind ~= "Income" then
			continue
		end
		local zones = plot:FindFirstChild("Zones")
		local zone = zones and zones:FindFirstChild(definition.ZoneId)
		local bounds = zone and zone:FindFirstChild("Bounds")
		if not bounds or (not bounds:IsA("Folder") and not bounds:IsA("Model")) then
			continue
		end
		for _, child in bounds:GetChildren() do
			if child:IsA("BasePart")
				and TerritoryPointRules.Check(child.CFrame, child.Size, entryPoint).Allowed
			then
				return plot.Name, definition.ZoneId, nil
			end
		end
	end

	return plot.Name, nil, "SoloAttackRegionUnavailable"
end

return WorkspaceSoloAttackAreaAccess
