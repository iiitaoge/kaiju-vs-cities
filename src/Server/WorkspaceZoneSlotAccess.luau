local ZoneSlotAccess = require(script.Parent.ZoneSlotAccess)

local WorkspaceZoneSlotAccess = {}

export type SlotDefinition = {
	SlotId: string,
	Kind: string,
}

export type ZoneDefinition = {
	ZoneId: string,
	Kind: string,
	Slots: { [string]: SlotDefinition },
}

export type CreateOptions = {
	GetPlot: (Player) -> Model?,
	GetZoneDefinitions: () -> { ZoneDefinition },
	IsZoneUnlocked: (Player, string) -> boolean,
}

-- 场景路径：Plot/Zones/<ZoneId>/Slots/<SlotId: BasePart>。
-- 适配器只做稳定身份和 Instance 关联，不执行任何 SlotKind 业务。
function WorkspaceZoneSlotAccess.Create(options: CreateOptions): ZoneSlotAccess.Access
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.GetPlot) == "function", "GetPlot 必须是 function")
	assert(type(options.GetZoneDefinitions) == "function", "GetZoneDefinitions 必须是 function")
	assert(type(options.IsZoneUnlocked) == "function", "IsZoneUnlocked 必须是 function")

	return {
		ListUnlockedSlots = function(player: Player, slotKind: string?): { ZoneSlotAccess.Slot }
			if slotKind ~= nil and (type(slotKind) ~= "string" or slotKind == "") then
				return {}
			end
			local plot = options.GetPlot(player)
			if not plot then
				return {}
			end
			local zones = plot:FindFirstChild("Zones")
			if not zones or not zones:IsA("Folder") then
				return {}
			end

			local snapshots = {}
			for _, definition in options.GetZoneDefinitions() do
				if not options.IsZoneUnlocked(player, definition.ZoneId) then
					continue
				end
				local zone = zones:FindFirstChild(definition.ZoneId)
				local slots = if zone then zone:FindFirstChild("Slots") else nil
				if not slots or not slots:IsA("Folder") then
					continue
				end
				for id, slotDefinition in pairs(definition.Slots) do
					if slotKind == nil or slotDefinition.Kind == slotKind then
						local point = slots:FindFirstChild(id)
						if point and point:IsA("BasePart") then
							table.insert(snapshots, {
								ZoneId = definition.ZoneId,
								ZoneKind = definition.Kind,
								SlotId = id,
								SlotKind = slotDefinition.Kind,
								Point = point,
							})
						end
					end
				end
			end

			table.sort(snapshots, function(a, b)
				return a.SlotId < b.SlotId
			end)
			return snapshots
		end,
	}
end

return WorkspaceZoneSlotAccess
