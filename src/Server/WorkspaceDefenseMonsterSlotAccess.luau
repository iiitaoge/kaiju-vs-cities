--[[
	职责：解析玩家 Plot 中收入区域的 DefenseMonsterSlot 直接子级。
	输入：Plot、RegionId。
	输出：唯一 BasePart 或稳定失败原因。
	不负责：目录配置、模型生成、Attribute 或状态。
]]

local UniqueNamedChildAccess = require(script.Parent.UniqueNamedChildAccess)

local WorkspaceDefenseMonsterSlotAccess = {}

function WorkspaceDefenseMonsterSlotAccess.Resolve(plot: Model, regionId: string): (BasePart?, string?)
	if typeof(plot) ~= "Instance" or not plot:IsA("Model") then
		return nil, "InvalidPlot"
	end
	local zones = plot:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(regionId)
	if not zone or not (zone:IsA("Folder") or zone:IsA("Model")) then
		return nil, "MissingDefenseMonsterRegion"
	end
	local slot, duplicated = UniqueNamedChildAccess.Find(zone, "DefenseMonsterSlot")
	if duplicated then
		return nil, "DuplicateDefenseMonsterSlot"
	end
	if not slot or not slot:IsA("BasePart") then
		return nil, "MissingDefenseMonsterSlot"
	end
	return slot, nil
end

return WorkspaceDefenseMonsterSlotAccess
