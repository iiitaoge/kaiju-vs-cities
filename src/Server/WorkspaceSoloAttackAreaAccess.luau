--[[
	职责：读取单人空地出征的服务器权威范围。
	输入：无；输出：当前 Bounds CFrame/Size，或稳定失败原因。
	内部算法：按配置名称读取 Workspace 顶层 BasePart，并验证正 X/Z 尺寸。
	不负责：玩家数量、点击校验、相机、怪兽移动或修改场景。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoloMonsterAttackConfigs = require(
	ReplicatedStorage.Shared.Monster.SoloMonsterAttackConfigs
)

local WorkspaceSoloAttackAreaAccess = {}

export type Area = {
	CFrame: CFrame,
	Size: Vector3,
}

function WorkspaceSoloAttackAreaAccess.Resolve(): (Area?, string?)
	local instance = workspace:FindFirstChild(SoloMonsterAttackConfigs.BoundsPartName)
	if not instance or not instance:IsA("BasePart") then
		return nil, "SoloAttackBoundsUnavailable"
	end
	local size = instance.Size
	if size.X <= 0 or size.Z <= 0 then
		return nil, "InvalidSoloAttackBounds"
	end
	return {
		CFrame = instance.CFrame,
		Size = size,
	}, nil
end

return WorkspaceSoloAttackAreaAccess
