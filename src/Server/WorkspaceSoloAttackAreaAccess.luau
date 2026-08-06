--[[
	职责：读取当前展示空 Plot 的服务器权威单人出征范围。
	输入：无；输出：空 Plot/AttackViewBounds 的 CFrame/Size，或稳定失败原因。
	内部算法：读取 PlayerPlotAssignmentService 维护的唯一展示空 Plot，并验证其 AttackViewBounds。
	不负责：玩家数量、点击校验、相机、怪兽移动、Plot 分配或修改场景。
]]

local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)

local WorkspaceSoloAttackAreaAccess = {}

export type Area = {
	CFrame: CFrame,
	Size: Vector3,
}

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
	}, nil
end

return WorkspaceSoloAttackAreaAccess
