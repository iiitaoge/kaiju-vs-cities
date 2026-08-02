local LocalBuildingController = require(script.Parent.Building.LocalBuildingController)
local LocalBuildingInteractionController = require(script.Parent.Building.LocalBuildingInteractionController)

local function bindInteractions(buildings)
	for _, building in buildings do
		LocalBuildingInteractionController.Bind(building.HouseId, building.Model)
	end

	return buildings
end

-- 按钮功能登记表
local handlers = {
	Build = function(action)
		return bindInteractions(LocalBuildingController.Build(action.JobName))
	end,

	Upgrade = function(action)
		return bindInteractions(LocalBuildingController.Upgrade(action.JobName))
	end,
}

local LocalActionController = {}

function LocalActionController.Run(action)
	local handler = assert(handlers[action.Kind], string.format("未知的本地 Action：%s", tostring(action.Kind)))
	return handler(action)
end

return LocalActionController
