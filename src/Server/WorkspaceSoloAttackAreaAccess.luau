--[[
	职责：读取固定单人演示 Plot 的服务器权威出征范围和可攻击区域。
	输入：无，或命令锁定的 PlotName 与攻击落点。
	输出：演示 Plot 的总视野、当前仍有房屋的 R1/R2 Bounds，以及落点所属区域。
	不负责：玩家数量、点击提交、相机、怪兽移动、Plot 分配或修改场景。
]]

local SoloShowcaseRuntimeService = require(script.Parent.SoloShowcaseRuntimeService)

local WorkspaceSoloAttackAreaAccess = {}

export type Area = SoloShowcaseRuntimeService.Area

function WorkspaceSoloAttackAreaAccess.Resolve(): (Area?, string?)
	return SoloShowcaseRuntimeService.GetArea()
end

-- 输入：命令接受时锁定的展示 Plot 名称，以及单人攻击落点。
-- 输出：展示 Plot 名称与落点所属 R1/R2 区域；无法落入可攻击区域时返回原因。
-- 内部算法：复用固定演示运行时按当前存活房屋筛选的 Bounds。
-- 不负责：判断单人攻击合法性、移动怪兽、选择相机参数或发送网络事件。
function WorkspaceSoloAttackAreaAccess.ResolveCameraTarget(
	plotName: string?,
	entryPoint: Vector3
): (string?, string?, string?)
	local plot = SoloShowcaseRuntimeService.GetPlot()
	if not plot or (plotName ~= nil and plotName ~= "" and plot.Name ~= plotName) then
		return nil, nil, "SoloShowcasePlotUnavailable"
	end

	local regionId, reason = SoloShowcaseRuntimeService.ResolveRegion(
		plot.Name,
		entryPoint
	)
	if not regionId then
		return plot.Name, nil, reason or "SoloAttackRegionUnavailable"
	end
	return plot.Name, regionId, nil
end

return WorkspaceSoloAttackAreaAccess
