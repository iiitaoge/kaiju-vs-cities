local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ButtonConfigs = require(ReplicatedStorage.Shared.Button.ButtonConfigs)
local MoneyProtocol = require(ReplicatedStorage.Shared.Economy.MoneyProtocol)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local LocalButtonController = require(script.Parent.LocalButtonController)
local LocalPlotButtonAccess = require(script.Parent.LocalPlotButtonAccess)
local LocalButtonWorldUIController = require(script.Parent.LocalButtonWorldUIController)
local TipBlackController = require(script.Parent.Parent.UI.TipBlackController)
local SoundController = require(script.Parent.Parent.Sound.SoundController)
local LocalUIModeService = require(script.Parent.Parent.UI.LocalUIModeService)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)

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
	local succeeded, action, state, presentation, reason, actionSucceeded = pcall(
		buttonRequest.InvokeServer,
		buttonRequest,
		buttonName,
		requestKind
	)
	if not succeeded then
		warn(string.format("按钮请求失败：%s/%s (%s)", buttonName, requestKind, tostring(action)))
		return nil, "Locked", { Enabled = false }, "RequestFailed", false
	end
	return action, state or "Locked", presentation, reason, actionSucceeded
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
				and not binding.IsRefreshing
			then
				binding.IsRefreshing = true
				local refreshVersion = binding.Version
				local _, state, presentation = request(buttonName, "GetState")
				binding.IsRefreshing = false
				if not binding.IsBusy
					and binding.Version == refreshVersion
					and state ~= "PlayerDataNotReady"
				then
					binding.Handle:SetState(state or binding.Config.InitialState)
					binding.WorldUIHandle:SetPresentation(presentation)
					binding.Handle:RefreshTouching()
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
				if not binding.IsBusy and not binding.IsRefreshing then
					binding.IsRefreshing = true
					local refreshVersion = binding.Version
					local _, state, presentation = request(buttonName, "GetState")
					binding.IsRefreshing = false
					if not binding.IsBusy
						and binding.Version == refreshVersion
						and state ~= "PlayerDataNotReady"
					then
						binding.Handle:SetState(state or binding.Config.InitialState)
						binding.WorldUIHandle:SetPresentation(presentation)
						binding.Handle:RefreshTouching()
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
			WorldUIHandle = LocalButtonWorldUIController.Bind(button),
			-- 首个 GetState 返回前必须视为忙碌，避免使用默认状态误触发。
			IsBusy = true,
			IsRefreshing = false,
			Version = 0,
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
					local _, state, presentation = request(buttonName, "GetState")
					if state ~= "PlayerDataNotReady" then
						binding.Handle:SetState(state or config.InitialState)
						binding.WorldUIHandle:SetPresentation(presentation)
						binding.IsBusy = false
						binding.Handle:RefreshTouching()
						task.defer(refreshRelatedButtons, config.Scope, config.ZoneId)
						return
					end
				end
			end)
		end

		binding.Handle = LocalButtonController.Bind(button, function()
			if binding.IsBusy
				or not binding.Handle:CanActivate()
			then
				return
			end

			SoundController.Play("Click")
			binding.Version += 1
			binding.IsBusy = true
			binding.Handle:SetState("Processing")

			local action, nextState, presentation, reason, actionSucceeded = request(
				buttonName,
				"Execute"
			)
			if actionSucceeded == true then
				SoundController.Play("Yes")
			elseif reason and reason ~= "PlayerDataNotReady" and reason ~= "RequestFailed" then
				SoundController.Play("No")
			end
			if reason == "InsufficientMoney" then
				TipBlackController.ShowInsufficientMoney()
			end
			if config.ActionId == "R3Unlock" and actionSucceeded == true then
				TipBlackController.ShowVehicleUnlocked()
			end
			if action then
				runAction(action)
			end

			if nextState == "PlayerDataNotReady" then
				refreshWhenDataReady()
			else
				binding.Handle:SetState(nextState)
				binding.WorldUIHandle:SetPresentation(presentation)
				binding.IsBusy = false
				binding.Handle:RefreshTouching()
				scheduleRefreshAllButtons()
			end
		end)

		local _, initialState, initialPresentation = request(buttonName, "GetState")
		if initialState == "PlayerDataNotReady" then
			refreshWhenDataReady()
		else
			binding.Handle:SetState(initialState or config.InitialState)
			binding.WorldUIHandle:SetPresentation(initialPresentation)
			binding.IsBusy = false
			binding.Handle:RefreshTouching()
		end
	end

	Players.LocalPlayer:GetAttributeChangedSignal(MoneyProtocol.BalanceAttributeName):Connect(
		scheduleRefreshAllButtons
	)
	LocalUIModeService.Observe(function()
		local enabled = LocalUIModeService.IsAllowed(
			UIModeVisibilityRules.Channels.Gameplay
		)
		for _, binding in bindings do
			binding.Handle:SetInputEnabled(enabled)
		end
	end)
end

return ButtonController
