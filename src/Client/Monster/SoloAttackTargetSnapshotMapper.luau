--[[
	职责：把服务端固定演示场景快照转换为客户端选点目标。
	输入：未知 SoloTarget 快照；输出：字段完整的 Solo Target 或 nil。
	内部算法：验证总视野和每个可攻击区域的 CFrame/正尺寸，只复制有效区域。
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
		and value.Size.Y > 0
		and value.Size.Z > 0
end

function SoloAttackTargetSnapshotMapper.Map(value)
	if type(value) ~= "table" or not validBounds(value.AttackView) then
		return nil
	end

	local territories = {}
	if type(value.Territories) == "table" then
		for _, territory in value.Territories do
			if type(territory) == "table"
				and type(territory.ZoneId) == "string"
				and territory.ZoneId ~= ""
				and type(territory.BoundsId) == "string"
				and territory.BoundsId ~= ""
				and validBounds(territory)
			then
				table.insert(territories, {
					ZoneId = territory.ZoneId,
					BoundsId = territory.BoundsId,
					CFrame = territory.CFrame,
					Size = territory.Size,
					AttackInProgress = territory.AttackInProgress == true,
				})
			end
		end
	end
	if #territories == 0 then
		return nil
	end

	return {
		Kind = "Solo",
		DisplayName = SoloMonsterAttackConfigs.DisplayName,
		AttackView = {
			CFrame = value.AttackView.CFrame,
			Size = value.AttackView.Size,
		},
		UnlockedTerritories = territories,
	}
end

return SoloAttackTargetSnapshotMapper
