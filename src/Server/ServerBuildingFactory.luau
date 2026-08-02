--[[
	职责：
	- 从建筑模板创建一个服务器权威的静态运行时模型。

	输入：
	- template：建筑模板。
	- targetPivot：调用方已经计算好的最终模型 Pivot。
	- parent：该玩家 Plot/Runtime/Buildings Folder。
	- identity：玩家、房屋、Zone 和 Slot 的稳定身份。

	输出：
	- 已经放入 parent 的建筑 Model。

	内部算法：
	- Clone 模板，先写入身份和静态零件属性，再定位并一次性放入运行时树。

	不负责：
	- 不读取玩家状态，不解析模板，不计算建筑位置，不维护运行时索引。
]]

local ServerBuildingFactory = {}

export type Identity = {
	OwnerUserId: number,
	HouseId: string,
	ZoneId: string,
	SlotId: string,
	Level: number,
}

local function assertNonEmpty(value: string, fieldName: string)
	assert(type(value) == "string" and value ~= "", fieldName .. " 必须是非空字符串")
end

function ServerBuildingFactory.Create(
	template: Model,
	targetPivot: CFrame,
	parent: Folder,
	identity: Identity
): Model
	assert(typeof(template) == "Instance" and template:IsA("Model"), "template 必须是 Model")
	assert(typeof(targetPivot) == "CFrame", "targetPivot 必须是 CFrame")
	assert(typeof(parent) == "Instance" and parent:IsA("Folder"), "parent 必须是 Folder")
	assert(type(identity) == "table", "identity 必须是 table")
	assert(
		type(identity.OwnerUserId) == "number"
			and identity.OwnerUserId == identity.OwnerUserId
			and identity.OwnerUserId % 1 == 0,
		"OwnerUserId 必须是整数"
	)
	assertNonEmpty(identity.HouseId, "HouseId")
	assertNonEmpty(identity.ZoneId, "ZoneId")
	assertNonEmpty(identity.SlotId, "SlotId")
	assert(
		type(identity.Level) == "number"
			and identity.Level < math.huge
			and identity.Level >= 1
			and identity.Level % 1 == 0,
		"Level 必须是有限正整数"
	)

	local model = template:Clone()
	model.Name = identity.HouseId
	model:SetAttribute("BuildingOwnerUserId", identity.OwnerUserId)
	model:SetAttribute("BuildingHouseId", identity.HouseId)
	model:SetAttribute("BuildingZoneId", identity.ZoneId)
	model:SetAttribute("BuildingSlotId", identity.SlotId)
	model:SetAttribute("BuildingLevel", identity.Level)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	model:PivotTo(targetPivot)
	model.Parent = parent
	return model
end

return ServerBuildingFactory
