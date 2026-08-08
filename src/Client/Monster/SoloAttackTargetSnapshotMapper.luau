--[[
	职责：把服务端展示空 Plot 快照转换为客户端选点目标。
	输入：未知 SoloTarget 快照；输出：字段完整的 Solo Target 或 nil。
	内部算法：验证 AttackView 与 Bounds 的 CFrame/正尺寸并复制字段。
	不负责：读取 Workspace、玩家查询、相机、落点校验或网络。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoloMonsterAttackConfigs = require(
	ReplicatedStorage.Shared.Monster.SoloMonsterAttackConfigs
)

local SoloAttackTargetSnapshotMapper = {}

local function validBounds(value): boolean
	return type(value) == "table"
		and typeof(value.CFrame) == "CFrame"
		and typeof(value.Size) == "Vector3"
		and value.Size.X > 0
		and value.Size.Z > 0
end

function SoloAttackTargetSnapshotMapper.Map(value)
	if type(value) ~= "table"
		or not validBounds(value.AttackView)
		or not validBounds(value.Bounds) then
		return nil
	end
	return {
		Kind = "Solo",
		DisplayName = SoloMonsterAttackConfigs.DisplayName,
		AttackView = {
			CFrame = value.AttackView.CFrame,
			Size = value.AttackView.Size,
		},
		UnlockedTerritories = {
			{
				ZoneId = "Solo",
				BoundsId = SoloMonsterAttackConfigs.BoundsPartName,
				CFrame = value.Bounds.CFrame,
				Size = value.Bounds.Size,
				AttackInProgress = false,
			},
		},
	}
end

return SoloAttackTargetSnapshotMapper
