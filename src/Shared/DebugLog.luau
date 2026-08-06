local DebugLog = {}

local ENABLED = true
local MODULES = {
	AttackSelectionCoordinates = true,
	HouseInteractionService = false,
	MoneyService = false,
}

function DebugLog.Create(moduleName: string)
	return function(...)
		if ENABLED and MODULES[moduleName] then
			print(string.format("[%s]", moduleName), ...)
		end
	end
end

return DebugLog
