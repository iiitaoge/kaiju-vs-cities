--[[
	职责：只读取并验证服务器运行时防御塔的稳定 Attributes。
	输入：Model 或 BasePart。
	输出：身份快照或稳定失败原因。
	不负责：查 Plot、读配置、检查解锁、目标选择或伤害。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local RuntimeDefenseTowerIdentity = {}

export type Identity = {
	OwnerUserId: number,
	TowerId: string,
	ZoneId: string,
	SlotId: string,
	ConfigId: string,
	Active: boolean,
}

function RuntimeDefenseTowerIdentity.Read(instance: Instance): (Identity?, string?)
	if typeof(instance) ~= "Instance"
		or (not instance:IsA("Model") and not instance:IsA("BasePart")) then
		return nil, "TowerInstanceUnsupported"
	end
	local ownerUserId = instance:GetAttribute("DefenseTowerOwnerUserId")
	local towerId = instance:GetAttribute("DefenseTowerId")
	local zoneId = instance:GetAttribute("DefenseTowerZoneId")
	local slotId = instance:GetAttribute("DefenseTowerSlotId")
	local configId = instance:GetAttribute("DefenseTowerConfigId")
	local active = instance:GetAttribute("DefenseTowerActive")
	if type(ownerUserId) ~= "number" or ownerUserId == 0 or ownerUserId % 1 ~= 0 then
		return nil, "InvalidTowerOwnerUserId"
	end
	if not ValueValidation.IsNonEmptyString(towerId) then
		return nil, "InvalidTowerId"
	end
	if not ValueValidation.IsNonEmptyString(zoneId) then
		return nil, "InvalidTowerZoneId"
	end
	if not ValueValidation.IsNonEmptyString(slotId) then
		return nil, "InvalidTowerSlotId"
	end
	if not ValueValidation.IsNonEmptyString(configId) then
		return nil, "InvalidTowerConfigId"
	end
	if type(active) ~= "boolean" then
		return nil, "InvalidTowerActive"
	end
	return {
		OwnerUserId = ownerUserId,
		TowerId = towerId,
		ZoneId = zoneId,
		SlotId = slotId,
		ConfigId = configId,
		Active = active,
	}, nil
end

return RuntimeDefenseTowerIdentity
