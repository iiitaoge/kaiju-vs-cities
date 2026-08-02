local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ButtonConfigs = require(ReplicatedStorage.Shared.Button.ButtonConfigs)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local LocalButtonController = require(script.Parent.LocalButtonController)
local LocalPlotButtonAccess = require(script.Parent.LocalPlotButtonAccess)

local buttonRequest = InstancePath.Get("ReplicatedStorage/Remotes/ButtonRequest")
assert(buttonRequest:IsA("RemoteFunction"), "ButtonRequest 必须是 RemoteFunction")

local ButtonController = {}

local function getButton(buttonName: string, config): Model
	if config.Scope == "Global" then
		local button = InstancePath.Get(string.format("Workspace/Buttons/%s", buttonName))
		assert(button:IsA("Model"), string.format("按钮必须是 Model：%s", buttonName))
		return button
	end

	assert(config.Scope == "PlayerPlot", "未知按钮 Scope：" .. tostring(config.Scope))
	local button = LocalPlotButtonAccess.WaitFor(
		Players.LocalPlayer.UserId,
		config.ZoneId,
		buttonName,
		10
	)
	return assert(button, string.format("找不到玩家 Plot 按钮：%s/%s", config.ZoneId, buttonName))
end

local function request(buttonName: string, requestKind: string)
	local succeeded, action, state = pcall(
		buttonRequest.InvokeServer,
		buttonRequest,
		buttonName,
		requestKind
	)
	if not succeeded then
		warn(string.format("按钮请求失败：%s/%s (%s)", buttonName, requestKind, tostring(action)))
		return nil, "Locked"
	end
	return action, state or "Locked"
end

function ButtonController.Start(runAction)
	for buttonName, config in pairs(ButtonConfigs) do
		local button = getButton(buttonName, config)
		local isBusy = false
		local handle
		local refreshGeneration = 0

		local function refreshWhenDataReady()
			refreshGeneration += 1
			local generation = refreshGeneration
			isBusy = true
			handle:SetState("Processing")
			task.spawn(function()
				while generation == refreshGeneration and Players.LocalPlayer.Parent do
					task.wait(0.25)
					local _, state = request(buttonName, "GetState")
					if state ~= "PlayerDataNotReady" then
						handle:SetState(state or config.InitialState)
						isBusy = false
						return
					end
				end
			end)
		end

		handle = LocalButtonController.Bind(button, function()
			if isBusy then
				return
			end

			isBusy = true
			handle:SetState("Processing")

			local action, nextState = request(buttonName, "Execute")
			if action then
				runAction(action)
			end

			if nextState == "PlayerDataNotReady" then
				refreshWhenDataReady()
			else
				handle:SetState(nextState)
				isBusy = false
			end
		end)

		local _, initialState = request(buttonName, "GetState")
		if initialState == "PlayerDataNotReady" then
			refreshWhenDataReady()
		else
			handle:SetState(initialState or config.InitialState)
		end
	end
end

return ButtonController
