local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SecurityAnalyticsAggregator = require(
	script.Parent.Parent.Analytics.SecurityAnalyticsAggregator
)
local ButtonActionExecutor = require(script.Parent.ButtonActionExecutor)
local ButtonActions = require(script.Parent.ButtonActions)
local PlotButtonAccess = require(script.Parent.PlotButtonAccess)
local PlayerPlotAssignmentService = require(script.Parent.Parent.PlayerPlotAssignmentService)
local PlayerDataReadyService = require(script.Parent.Parent.PlayerDataReadyService)
local ButtonConfigs = require(ReplicatedStorage.Shared.Button.ButtonConfigs)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)

local buttonRequest = InstancePath.Get("ReplicatedStorage/Remotes/ButtonRequest")
assert(buttonRequest:IsA("RemoteFunction"), "ButtonRequest 必须是 RemoteFunction")

local progressByPlayer = setmetatable({}, { __mode = "k" })

local function canUseConfiguredButton(player: Player, buttonName: string, config, execute: boolean): boolean
	if config.Scope == "Global" then
		return true
	end
	if config.Scope ~= "PlayerPlot" then
		return false
	end
	if type(config.ZoneId) ~= "string"
		or type(config.MaxActivationDistance) ~= "number"
		or config.MaxActivationDistance <= 0 then
		return false
	end

	local plot = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return false
	end
	local _, pull = PlotButtonAccess.Get(plot, config.ZoneId, buttonName)
	if not pull then
		return false
	end
	if not execute then
		return true
	end
	local allowed = PlotButtonAccess.CheckActivation(
		player.Character,
		pull,
		config.MaxActivationDistance
	)
	return allowed
end

buttonRequest.OnServerInvoke = function(player, buttonName, requestKind)
	if PlayerDataReadyService.Get(player).Status ~= "Ready" then
		return nil, "PlayerDataNotReady", { Enabled = false }, "PlayerDataNotReady", false
	end
	if type(buttonName) ~= "string" then
		SecurityAnalyticsAggregator.Record(player, "ButtonRequest", "InvalidButtonName")
		return nil, "Locked", { Enabled = false }, "InvalidButtonName", false
	end
	requestKind = requestKind or "Execute"
	if requestKind ~= "Execute" and requestKind ~= "GetState" then
		SecurityAnalyticsAggregator.Record(player, "ButtonRequest", "InvalidRequestKind")
		return nil, "Locked", { Enabled = false }, "InvalidRequestKind", false
	end

	local buttonConfig = ButtonConfigs[buttonName]
	if not buttonConfig then
		SecurityAnalyticsAggregator.Record(player, "ButtonRequest", "UnknownButton")
		return nil, "Locked", { Enabled = false }, "UnknownButton", false
	end
	if not canUseConfiguredButton(player, buttonName, buttonConfig, requestKind == "Execute") then
		SecurityAnalyticsAggregator.Record(player, "ButtonRequest", "ActivationRejected")
		return nil, "Locked", { Enabled = false }, "ActivationRejected", false
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
		return nil, "Locked", { Enabled = false }, "ActionUnavailable", false
	end
	if requestKind == "GetState" then
		local state = if action.RunOn == "Server"
			then ButtonActionExecutor.GetState(player, action)
			else nil
		return nil,
			state or buttonConfig.InitialState,
			ButtonActionExecutor.GetPresentation(player, action),
			nil,
			nil
	end

	local clientAction
	local actionState
	local actionReason
	if action.RunOn == "Client" then
		clientAction = action
	else
		clientAction, actionState, actionReason = ButtonActionExecutor.Run(player, action)
	end
	local actionSucceeded = if action.RunOn == "Client"
		then true
		else actionReason == nil

	if action.Repeat then
		local nextState = actionState
			or ButtonActionExecutor.GetState(player, action)
			or buttonConfig.InitialState
		return clientAction,
			nextState,
			ButtonActionExecutor.GetPresentation(player, action),
			actionReason,
			actionSucceeded
	end

	progress[buttonName] = index + 1
	local nextAction = actions[index + 1]
	return clientAction,
		if nextAction then "Ready" else "Locked",
		if nextAction
			then ButtonActionExecutor.GetPresentation(player, nextAction)
			else { Enabled = false },
		actionReason,
		actionSucceeded
end
