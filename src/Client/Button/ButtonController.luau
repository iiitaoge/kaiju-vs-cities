local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonConfigs = require(ReplicatedStorage.Shared.Button.ButtonConfigs)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local LocalButtonController = require(script.Parent.LocalButtonController)

local buttonRequest = InstancePath.Get("ReplicatedStorage/Remotes/ButtonRequest")
assert(buttonRequest:IsA("RemoteFunction"), "ButtonRequest 必须是 RemoteFunction")

local ButtonController = {}

function ButtonController.Start(runAction)
	for buttonName, config in pairs(ButtonConfigs) do
		local button = InstancePath.Get(string.format("Workspace/Buttons/%s", buttonName))
		assert(button:IsA("Model"), string.format("按钮必须是 Model：%s", buttonName))
		local isBusy = false
		local handle

		handle = LocalButtonController.Bind(button, function()
			if isBusy then
				return
			end

			isBusy = true
			handle:SetState("Processing")

			local action, nextState = buttonRequest:InvokeServer(buttonName)	-- 发送服务端，服务端返回
			if action then
				runAction(action)
			end

			handle:SetState(nextState)
			isBusy = false
		end)

		handle:SetState(config.InitialState)
	end
end

return ButtonController
