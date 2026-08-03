--[[
	职责：从服务器运行时建筑读取并验证稳定身份。
	输入：一个 Model。
	输出：OwnerUserId、HouseId、ZoneId、SlotId；失败时返回 nil 和原因。
	内部算法：只读取 Building* Attributes 并验证基本类型。
	不负责：不查询玩家、不读取状态、不修改 Model。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)

local RuntimeBuildingIdentity = {}

export type Identity = {
	OwnerUserId: number,
	HouseId: string,
	ZoneId: string,
	SlotId: string,
	Level: number,
}

local function isInteger(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value > -math.huge
		and value % 1 == 0
end

function RuntimeBuildingIdentity.Read(model: Model): (Identity?, string?)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil, "BuildingNotModel"
	end

	local ownerUserId = model:GetAttribute("BuildingOwnerUserId")
	local houseId = model:GetAttribute("BuildingHouseId")
	local zoneId = model:GetAttribute("BuildingZoneId")
	local slotId = model:GetAttribute("BuildingSlotId")
	local level = model:GetAttribute("BuildingLevel")
	if not isInteger(ownerUserId) or ownerUserId == 0 then
		return nil, "InvalidBuildingOwnerUserId"
	end
	if not ValueValidation.IsNonEmptyString(houseId) then
		return nil, "InvalidBuildingHouseId"
	end
	if not ValueValidation.IsNonEmptyString(zoneId) then
		return nil, "InvalidBuildingZoneId"
	end
	if not ValueValidation.IsNonEmptyString(slotId) then
		return nil, "InvalidBuildingSlotId"
	end
	if not isInteger(level) or level < 1 then
		return nil, "InvalidBuildingLevel"
	end

	return {
		OwnerUserId = ownerUserId,
		HouseId = houseId,
		ZoneId = zoneId,
		SlotId = slotId,
		Level = level,
	}, nil
end

return RuntimeBuildingIdentity
