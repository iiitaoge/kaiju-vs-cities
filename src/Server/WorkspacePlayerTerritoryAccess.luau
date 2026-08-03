local PlayerTerritoryAccess = require(script.Parent.PlayerTerritoryAccess)

local WorkspacePlayerTerritoryAccess = {}

local function isContainer(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("Folder") or instance:IsA("Model"))
end

export type ZoneDefinition = {
	ZoneId: string,
}

export type CreateOptions = {
	GetPlot: (Player) -> Model?,
	GetZoneDefinitions: () -> { ZoneDefinition },
	IsZoneUnlocked: (Player, string) -> boolean,
}

-- 输入依赖回调；输出只读取 Workspace 的已解锁 Zone 范围适配器。
-- 场景路径：Plot/Zones/<ZoneId>/Bounds/<BoundsId: BasePart>；Bounds 可为 Folder 或 Model。
function WorkspacePlayerTerritoryAccess.Create(options: CreateOptions): PlayerTerritoryAccess.Access
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.GetPlot) == "function", "GetPlot 必须是 function")
	assert(type(options.GetZoneDefinitions) == "function", "GetZoneDefinitions 必须是 function")
	assert(type(options.IsZoneUnlocked) == "function", "IsZoneUnlocked 必须是 function")

	return {
		ListUnlockedTerritories = function(player: Player): { PlayerTerritoryAccess.Territory }
			local plot = options.GetPlot(player)
			if not plot then
				return {}
			end
			local zones = plot:FindFirstChild("Zones")
			if not zones or not zones:IsA("Folder") then
				return {}
			end

			local territories = {}
			for _, definition in options.GetZoneDefinitions() do
				if not options.IsZoneUnlocked(player, definition.ZoneId) then
					continue
				end
				local zone = zones:FindFirstChild(definition.ZoneId)
				local bounds = if zone then zone:FindFirstChild("Bounds") else nil
				if not isContainer(bounds) then
					continue
				end
				for _, child in bounds:GetChildren() do
					if child:IsA("BasePart") then
						table.insert(territories, {
							ZoneId = definition.ZoneId,
							BoundsId = child.Name,
							CFrame = child.CFrame,
							Size = child.Size,
						})
					end
				end
			end

			table.sort(territories, function(a, b)
				if a.ZoneId ~= b.ZoneId then
					return a.ZoneId < b.ZoneId
				end
				return a.BoundsId < b.BoundsId
			end)
			return territories
		end,
	}
end

return WorkspacePlayerTerritoryAccess
