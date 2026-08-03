--[[
	职责：解析服务器 Plot 中罐体的唯一世界定位 Part。
	输入：Plot、ZoneId、IncubatorSlotId。
	输出：Zones/<ZoneId>/IncubatorSlots/<SlotId>，或稳定失败原因。
	内部算法：固定路径、唯一名称、类型、身份 Attribute 和锚定状态验证。
	不负责：模板、Runtime、Clone、动画或怪兽出生点。
]]

local WorkspaceMonsterIncubatorSlotAccess = {}

local function findUniqueChild(parent: Instance, name: string): (Instance?, string?)
	local found = nil
	for _, child in parent:GetChildren() do
		if child.Name == name then
			if found then
				return nil, "DuplicateIncubatorSlot"
			end
			found = child
		end
	end
	return found, nil
end

function WorkspaceMonsterIncubatorSlotAccess.Resolve(
	plot: Model,
	zoneId: string,
	incubatorSlotId: string
): (BasePart?, string?)
	if typeof(plot) ~= "Instance" or not plot:IsA("Model") then
		return nil, "InvalidPlot"
	end
	if type(zoneId) ~= "string" or zoneId == "" then
		return nil, "InvalidZoneId"
	end
	if type(incubatorSlotId) ~= "string" or incubatorSlotId == "" then
		return nil, "InvalidIncubatorSlotId"
	end

	local zones = plot:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(zoneId)
	local slots = zone and zone:FindFirstChild("IncubatorSlots")
	if not slots or not slots:IsA("Folder") then
		return nil, "MissingIncubatorSlots"
	end
	local point, duplicateReason = findUniqueChild(slots, incubatorSlotId)
	if duplicateReason then
		return nil, duplicateReason
	end
	if not point or not point:IsA("BasePart") then
		return nil, "MissingIncubatorSlot"
	end
	if not point.Anchored then
		return nil, "IncubatorSlotMustBeAnchored"
	end
	if point:GetAttribute("SlotKind") ~= "MonsterIncubator"
		or point:GetAttribute("SlotId") ~= incubatorSlotId
		or point:GetAttribute("ZoneId") ~= zoneId then
		return nil, "IncubatorSlotIdentityMismatch"
	end
	return point, nil
end

return WorkspaceMonsterIncubatorSlotAccess
