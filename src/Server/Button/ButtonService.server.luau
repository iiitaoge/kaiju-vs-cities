local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonActionExecutor = require(script.Parent.ButtonActionExecutor)
local ButtonActions = require(script.Parent.ButtonActions)
local ButtonConfigs = require(ReplicatedStorage.Shared.Button.ButtonConfigs)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)

local buttonRequest = InstancePath.Get("ReplicatedStorage/Remotes/ButtonRequest")
assert(buttonRequest:IsA("RemoteFunction"), "ButtonRequest 必须是 RemoteFunction")

local progressByPlayer = setmetatable({}, { __mode = "k" })

buttonRequest.OnServerInvoke = function(player, buttonName)
	local buttonConfig = ButtonConfigs[buttonName]
	if not buttonConfig then
		return nil, "Locked"
	end

	local actions = assert(
		ButtonActions[buttonConfig.ActionId],
		string.format("按钮 ActionId 未配置：%s", buttonConfig.ActionId)
	)

	local progress = progressByPlayer[player] or {}
	progressByPlayer[player] = progress

	local index = progress[buttonName] or 1
	local action = actions[index]
	if not action then
		return nil, "Locked"
	end

	local clientAction
	local actionState
	if action.RunOn == "Client" then
		clientAction = action
	else
		clientAction, actionState = ButtonActionExecutor.Run(player, action)
	end

	if action.Repeat then
		return clientAction, actionState
	end

	progress[buttonName] = index + 1
	return clientAction, if actions[index + 1] then "Ready" else "Locked"
end
