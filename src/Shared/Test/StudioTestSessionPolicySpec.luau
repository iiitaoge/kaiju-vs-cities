local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EightPlayerCapacityAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.EightPlayerCapacityAcceptanceProtocol
)
local MultiplayerAttackAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.MultiplayerAttackAcceptanceProtocol
)
local StudioTestSessionPolicy = require(
	ServerScriptService.Server.StudioTestSessionPolicy
)

local StudioTestSessionPolicySpec = {}

function StudioTestSessionPolicySpec.Run(): boolean
	assert(
		StudioTestSessionPolicy.IsPersistenceDisabledForArgument(
			EightPlayerCapacityAcceptanceProtocol.TestArgument
		),
		"八人容量验收必须禁用真实存档"
	)
	assert(
		StudioTestSessionPolicy.IsPersistenceDisabledForArgument(
			MultiplayerAttackAcceptanceProtocol.TestArgument
		),
		"多人攻击验收必须禁用真实存档"
	)
	assert(
		not StudioTestSessionPolicy.IsPersistenceDisabledForArgument(nil),
		"nil 参数不得禁用存档"
	)
	for _, argument in { "", "OrdinaryStudioPlay", 123 } do
		assert(
			not StudioTestSessionPolicy.IsPersistenceDisabledForArgument(argument),
			"普通会话参数不得禁用存档"
		)
	end
	assert(table.isfrozen(StudioTestSessionPolicy), "测试会话策略必须只读")
	return true
end

return StudioTestSessionPolicySpec
