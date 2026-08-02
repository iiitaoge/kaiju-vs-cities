--[[
	职责：按固定场景合同解析玩家 Plot 中的实体按钮，并验证角色触发距离。

	输入：Plot、ZoneId、ButtonName；距离验证额外接收 Character 和最大距离。
	输出：按钮 Model、Pull；失败时返回稳定 Reason。
	内部算法：只走 Plot/Zones/<ZoneId>/Buttons/<ButtonName>，再比较 HumanoidRootPart 到 Pull 的距离。

	不负责：玩家 Plot 分配、按钮业务、状态查询或 Remote。
]]

local PlotButtonAccess = {}

function PlotButtonAccess.Get(
	plot: Model,
	zoneId: string,
	buttonName: string
): (Model?, BasePart?, string?)
	if not plot:IsA("Model") then
		return nil, nil, "InvalidPlot"
	end
	local zones = plot:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(zoneId)
	local buttons = zone and zone:FindFirstChild("Buttons")
	local button = buttons and buttons:FindFirstChild(buttonName)
	if not button or not button:IsA("Model") then
		return nil, nil, "ButtonUnavailable"
	end
	local pull = button:FindFirstChild("Pull")
	if not pull or not pull:IsA("BasePart") then
		return nil, nil, "ButtonPullUnavailable"
	end
	return button, pull, nil
end

function PlotButtonAccess.CheckActivation(
	character: Model?,
	pull: BasePart,
	maxDistance: number
): (boolean, string?)
	if not character then
		return false, "CharacterUnavailable"
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, "CharacterRootUnavailable"
	end
	if (root.Position - pull.Position).Magnitude > maxDistance then
		return false, "ButtonTooFar"
	end
	return true, nil
end

return PlotButtonAccess
