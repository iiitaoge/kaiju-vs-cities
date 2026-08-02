local DebugLog = {}

local ENABLED = true
local MODULES = {
	HouseInteractionService = true,
	MoneyService = true,
}

function DebugLog.Create(moduleName: string)
	return function(...)
		if ENABLED and MODULES[moduleName] then
			print(string.format("[%s]", moduleName), ...)
		end
	end
end

return DebugLog
