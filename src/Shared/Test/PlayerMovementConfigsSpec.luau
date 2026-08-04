local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerMovementConfigs = require(
	ReplicatedStorage.Shared.Player.PlayerMovementConfigs
)

local Spec = {}

function Spec.Run(): boolean
	assert(PlayerMovementConfigs.WalkSpeed == 40, "人物 WalkSpeed 必须为 40 studs/s")
	return true
end

return Spec
