local ServerScriptService = game:GetService("ServerScriptService")

local ContentContractValidator = require(ServerScriptService.Server.ContentContractValidator)

local ContentContractValidatorSpec = {}

function ContentContractValidatorSpec.Run(): boolean
	local result = ContentContractValidator.Validate()
	assert(result.Valid, "ContentContractValidatorSpec: " .. table.concat(result.Errors, "; "))
	return true
end

return ContentContractValidatorSpec
