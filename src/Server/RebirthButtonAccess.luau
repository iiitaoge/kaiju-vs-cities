--[[
	职责：解析玩家所属 Plot 的重生按钮并验证服务端激活距离。
	输入：在线 Player。
	输出：允许状态和稳定失败原因。
	内部算法：先定位玩家 Plot，再从 Plot/Buttons 按配置名找到 Model/Pull，并校验距离。
	不负责：UI 显示、资格、重生、存档或按钮动画。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthProgressionConfigs = require(
	ReplicatedStorage.Shared.Progression.RebirthProgressionConfigs
)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local PlotButtonAccess = require(script.Parent.Button.PlotButtonAccess)

local RebirthButtonAccess = {}

function RebirthButtonAccess.CheckActivation(player: Player): (boolean, string?)
	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return false, plotReason or "PlayerHasNoPlot"
	end
	local _, pull, buttonReason = PlotButtonAccess.GetRoot(
		plot,
		RebirthProgressionConfigs.Button.ButtonName
	)
	if not pull then
		if buttonReason == "ButtonPullUnavailable" then
			return false, "RebirthButtonPullUnavailable"
		end
		return false, "RebirthButtonUnavailable"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, "CharacterRootUnavailable"
	end
	if (root.Position - pull.Position).Magnitude
		> RebirthProgressionConfigs.Button.MaxActivationDistance then
		return false, "RebirthButtonTooFar"
	end
	return true, nil
end

return table.freeze(RebirthButtonAccess)
