local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ButtonConfigs = require(ReplicatedStorage.Shared.Button.ButtonConfigs)
local MoneyProtocol = require(ReplicatedStorage.Shared.Economy.MoneyProtocol)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local LocalButtonController = require(script.Parent.LocalButtonController)
local LocalPlotButtonAccess = require(script.Parent.LocalPlotButtonAccess)

local buttonRequest = InstancePath.Get("ReplicatedStorage/Remotes/ButtonRequest")
assert(buttonRequest:IsA("RemoteFunction"), "ButtonRequest 必须是 RemoteFunction")

local ButtonController = {}

local function getButton(buttonName: string, config, ownPlot: Model?): Model?
	if config.Scope == "Global" then
		local button = InstancePath.Get(string.format("Workspace/Buttons/%s", buttonName))
		assert(button:IsA("Model"), string.format("按钮必须是 Model：%s", buttonName))
		return button
	end

	assert(config.Scope == "PlayerPlot", "未知按钮 Scope：" .. tostring(config.Scope))
	return if ownPlot
		then LocalPlotButtonAccess.FindInPlot(ownPlot, config.ZoneId, buttonName)
		else nil
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
	local ownPlot = LocalPlotButtonAccess.WaitForPlot(Players.LocalPlayer.UserId, 10)
	assert(ownPlot, "找不到本地玩家 Plot")
	local bindings = {}
	local refreshAllScheduled = false

	local function refreshRelatedButtons(scope: string, zoneId: string?)
		for buttonName, binding in bindings do
			if binding.Config.Scope == scope
				and binding.Config.ZoneId == zoneId
				and not binding.IsBusy
			then
				local _, state = request(buttonName, "GetState")
				if state ~= "PlayerDataNotReady" then
					binding.Handle:SetState(state or binding.Config.InitialState)
				end
			end
		end
	end

	local function scheduleRefreshAllButtons()
		if refreshAllScheduled then
			return
		end
		refreshAllScheduled = true
		task.defer(function()
			refreshAllScheduled = false
			for buttonName, binding in bindings do
				if not binding.IsBusy then
					local _, state = request(buttonName, "GetState")
					if state ~= "PlayerDataNotReady" then
						binding.Handle:SetState(state or binding.Config.InitialState)
					end
				end
			end
		end)
	end

	for buttonName, config in pairs(ButtonConfigs) do
		local button = getButton(buttonName, config, ownPlot)
		if not button then
			continue
		end
		local binding = {
			Config = config,
			Handle = nil,
			IsBusy = false,
		}
		bindings[buttonName] = binding
		local refreshGeneration = 0

		local function refreshWhenDataReady()
			refreshGeneration += 1
			local generation = refreshGeneration
			binding.IsBusy = true
			binding.Handle:SetState("Processing")
			task.spawn(function()
				while generation == refreshGeneration and Players.LocalPlayer.Parent do
					task.wait(0.25)
					local _, state = request(buttonName, "GetState")
					if state ~= "PlayerDataNotReady" then
						binding.Handle:SetState(state or config.InitialState)
						binding.IsBusy = false
						task.defer(refreshRelatedButtons, config.Scope, config.ZoneId)
						return
					end
				end
			end)
		end

		binding.Handle = LocalButtonController.Bind(button, function()
			if binding.IsBusy then
				return
			end

			binding.IsBusy = true
			binding.Handle:SetState("Processing")

			local action, nextState = request(buttonName, "Execute")
			if action then
				runAction(action)
			end

			if nextState == "PlayerDataNotReady" then
				refreshWhenDataReady()
			else
				binding.Handle:SetState(nextState)
				binding.IsBusy = false
				task.defer(refreshRelatedButtons, config.Scope, config.ZoneId)
			end
		end)

		local _, initialState = request(buttonName, "GetState")
		if initialState == "PlayerDataNotReady" then
			refreshWhenDataReady()
		else
			binding.Handle:SetState(initialState or config.InitialState)
		end
	end

	Players.LocalPlayer:GetAttributeChangedSignal(MoneyProtocol.BalanceAttributeName):Connect(
		scheduleRefreshAllButtons
	)
end

return ButtonController
