--[[
	职责：把共享人物移动配置应用到每次生成的玩家 Humanoid。
	输入：Apply 接收 Character Model；Start 注册玩家与角色生命周期。
	输出：Apply 返回是否成功和失败原因。
	内部算法：等待 Humanoid 就绪，然后设置权威 WalkSpeed。
	不负责：出生位置、冲刺、动画、体力或怪兽移动。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerMovementConfigs = require(
	ReplicatedStorage.Shared.Player.PlayerMovementConfigs
)

local PlayerCharacterMovementService = {}

local HUMANOID_TIMEOUT_SECONDS = 10
local started = false

function PlayerCharacterMovementService.Apply(character: Model): (boolean, string?)
	assert(
		typeof(character) == "Instance" and character:IsA("Model"),
		"character 必须是 Model"
	)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		local found = character:WaitForChild("Humanoid", HUMANOID_TIMEOUT_SECONDS)
		humanoid = if found and found:IsA("Humanoid") then found else nil
	end
	if not humanoid or not character.Parent then
		return false, "HumanoidUnavailable"
	end
	humanoid.WalkSpeed = PlayerMovementConfigs.WalkSpeed
	return true, nil
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.defer(PlayerCharacterMovementService.Apply, character)
	end)
	if player.Character then
		task.defer(PlayerCharacterMovementService.Apply, player.Character)
	end
end

function PlayerCharacterMovementService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(bindPlayer)
	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

return PlayerCharacterMovementService
