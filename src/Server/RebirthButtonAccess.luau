--[[
	职责：解析唯一全局重生按钮并验证服务端激活距离。
	输入：在线 Player。
	输出：允许状态和稳定失败原因。
	内部算法：按配置路径找到 Model/Pull，比较 HumanoidRootPart 到 Pull 的距离。
	不负责：UI 显示、资格、重生、存档或按钮动画。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local RebirthProgressionConfigs = require(
	ReplicatedStorage.Shared.Progression.RebirthProgressionConfigs
)

local RebirthButtonAccess = {}

function RebirthButtonAccess.CheckActivation(player: Player): (boolean, string?)
	local button = InstancePath.Find(RebirthProgressionConfigs.Button.ModelPath)
	if not button or not button:IsA("Model") then
		return false, "RebirthButtonUnavailable"
	end
	local pull = button:FindFirstChild("Pull")
	if not pull or not pull:IsA("BasePart") then
		return false, "RebirthButtonPullUnavailable"
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
