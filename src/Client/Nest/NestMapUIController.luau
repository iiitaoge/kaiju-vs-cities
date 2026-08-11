--[[
	职责：连接 Main.Map 的巢穴浏览、部署、召回和生命条表现。
	输入：Map UI 按钮、VehicleDeploymentState 和 NestMapRemoteClient 的状态/动作结果。
	输出：当前 Nest 的名称、每分钟收益、提示、占领载具血条和可用动作；Map 关闭时恢复镜头。
	内部算法：打开时定位 Nest0；左右按钮循环切换 Nest；普通浏览不显示部署，
	只有待部署载具存在且该 Nest 没有我方载具时显示 Deploy；我方已派遣时显示 Recall。
	不负责：巢穴占用、战斗、奖励、载具拥有关系或车辆列表渲染。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalUIVisibilityGate = require(
	script.Parent.Parent.UI.LocalUIVisibilityGate
)
local LocalGuiButtonState = require(
	script.Parent.Parent.UI.LocalGuiButtonState
)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local NestCatalog = require(ReplicatedStorage.Shared.Nest.NestCatalog)
local NestMapCameraConfigs = require(
	ReplicatedStorage.Shared.Nest.NestMapCameraConfigs
)
local VehicleDeploymentState = require(script.Parent.Parent.VehicleDeploymentState)
local NestMapCameraController = require(script.Parent.NestMapCameraController)
local NestMapRemoteClient = require(script.Parent.NestMapRemoteClient)
local NestMapSceneAccess = require(script.Parent.NestMapSceneAccess)
local SoundController = require(script.Parent.Parent.Sound.SoundController)
local CompactNumberFormatter = require(
	ReplicatedStorage.Shared.UI.CompactNumberFormatter
)

local NestMapUIController = {}

type TextTarget = TextLabel | TextButton

type References = {
	Root: GuiObject,
	Title: TextTarget,
	Val: TextTarget,
	ProgressBar: GuiObject,
	Bar: GuiObject,
	Tip: TextTarget,
	LeftButton: GuiButton,
	RightButton: GuiButton,
	DeployFrame: GuiObject,
	DeployButton: GuiButton,
	DeployValue: TextTarget,
	RecallFrame: GuiObject,
	RecallButton: GuiButton,
	RecallValue: TextTarget,
	ExitButton: GuiButton,
}

type Callbacks = {
	OnExit: (() -> ())?,
	OnVehicleStateChanged: (() -> ())?,
}

local localPlayer = Players.LocalPlayer
local references: References? = nil
local visibilityGate: LocalUIVisibilityGate.Handle? = nil
local callbacks: Callbacks = {
	OnExit = nil,
	OnVehicleStateChanged = nil,
}
local stateByNestId = {}
local selectedIndex = 1
local active = false
local actionBusy = false
local refreshInFlight = false
local pollingToken = 0
local actionToken = 0
local started = false

local function resolveChild(parent: Instance?, name: string): Instance?
	return if parent then parent:FindFirstChild(name) else nil
end

local function resolveGuiObject(parent: Instance?, name: string): GuiObject?
	local child = resolveChild(parent, name)
	return if child and child:IsA("GuiObject") then child else nil
end

local function resolveButton(parent: Instance?, name: string): GuiButton?
	local child = resolveChild(parent, name)
	return if child and child:IsA("GuiButton") then child else nil
end

local function resolveTextTarget(parent: Instance?, name: string): TextTarget?
	local child = resolveChild(parent, name)
	if child and (child:IsA("TextLabel") or child:IsA("TextButton")) then
		return child :: TextTarget
	end
	return nil
end

local function resolveReferences(playerGui: PlayerGui): (References?, string?)
	local main = playerGui:FindFirstChild("Main")
	local root = resolveGuiObject(main, "Map")
	local top = resolveGuiObject(root, "Top")
	local title = resolveTextTarget(top, "Title")
	local val = resolveTextTarget(top, "Val")
	local progressBar = resolveGuiObject(top, "ProgressBar")
	local bar = resolveGuiObject(progressBar, "Bar")
	local tip = resolveTextTarget(progressBar, "Tip")
	local leftButton = resolveButton(top, "Left")
	local rightButton = resolveButton(top, "Right")
	local down = resolveGuiObject(root, "Down")
	local deployFrame = resolveGuiObject(down, "Deploy")
	local deployButton = resolveButton(deployFrame, "Button")
	local deployValue = resolveTextTarget(deployButton, "Val")
	local recallFrame = resolveGuiObject(down, "Callback")
	local recallButton = resolveButton(recallFrame, "Button")
	local recallValue = resolveTextTarget(recallButton, "Val")
	local exitFrame = resolveGuiObject(down, "Exit")
	local exitButton = resolveButton(exitFrame, "Button")

	if not main then
		return nil, "MainGuiUnavailable"
	end
	if not root then
		return nil, "MapPanelUnavailable"
	end
	if not top then
		return nil, "MapTopUnavailable"
	end
	if not title then
		return nil, "MapTitleUnavailable"
	end
	if not val then
		return nil, "MapValUnavailable"
	end
	if not progressBar or not bar or not tip then
		return nil, "MapProgressBarUnavailable"
	end
	if not leftButton or not rightButton then
		return nil, "MapNavigationUnavailable"
	end
	if not deployFrame or not deployButton or not deployValue then
		return nil, "MapDeployUnavailable"
	end
	if not recallFrame or not recallButton or not recallValue then
		return nil, "MapRecallUnavailable"
	end
	if not exitFrame or not exitButton then
		return nil, "MapExitUnavailable"
	end

	return {
		Root = root,
		Title = title,
		Val = val,
		ProgressBar = progressBar,
		Bar = bar,
		Tip = tip,
		LeftButton = leftButton,
		RightButton = rightButton,
		DeployFrame = deployFrame,
		DeployButton = deployButton,
		DeployValue = deployValue,
		RecallFrame = recallFrame,
		RecallButton = recallButton,
		RecallValue = recallValue,
		ExitButton = exitButton,
	}, nil
end

local function setButtonEnabled(button: GuiButton, enabled: boolean)
	LocalGuiButtonState.SetEnabled(button, enabled)
end

local function getDefinitions()
	return NestCatalog.GetAll()
end

local function findIndex(nestId: string): number?
	for index, definition in getDefinitions() do
		if definition.NestId == nestId then
			return index
		end
	end
	return nil
end

local function getFirstIndex(): number
	return findIndex(NestMapCameraConfigs.FirstNestId) or 1
end

local function getSelectedDefinition()
	return getDefinitions()[selectedIndex]
end

local function getSelectedNestId(): string?
	local definition = getSelectedDefinition()
	return if definition then definition.NestId else nil
end

local function getSelectedSnapshot()
	local nestId = getSelectedNestId()
	return if nestId then stateByNestId[nestId] else nil
end

local function getSelectedRewardText(): string
	local definition = getSelectedDefinition()
	if not definition
		or type(definition.BaseDiamonds) ~= "number"
		or type(definition.BaseIntervalSeconds) ~= "number"
		or definition.BaseIntervalSeconds <= 0
	then
		return "Income unavailable"
	end

	local diamondsPerMinute = definition.BaseDiamonds * 60 / definition.BaseIntervalSeconds
	return "+" .. CompactNumberFormatter.Format(diamondsPerMinute) .. " diamonds/min"
end

local function applySelectedSnapshot()
	local current = references
	if not current then
		return
	end

	local snapshot = getSelectedSnapshot()
	local occupant = snapshot and snapshot.Occupant
	local ownVehicle = snapshot and snapshot.OwnVehicle
	local ownOccupant = occupant and occupant.UserId == localPlayer.UserId
	local deployment = VehicleDeploymentState.Get()

	current.Title.Text = if occupant and occupant.OwnerName
		then tostring(occupant.OwnerName)
		else "Neutral"
	current.Val.Text = getSelectedRewardText()

	local hasOccupant = occupant ~= nil
	current.ProgressBar.Visible = hasOccupant
	if hasOccupant then
		local maxHealth = if type(occupant.MaxHealth) == "number"
			then occupant.MaxHealth
			else 0
		local health = if type(occupant.Health) == "number" then occupant.Health else 0
		local ratio = if maxHealth > 0 then math.clamp(health / maxHealth, 0, 1) else 0
		current.Bar.Size = UDim2.new(ratio, 0, 1, 0)
		current.Tip.Text = if ownOccupant
			then "Your vehicle is holding this nest"
			else "Attack them to seize the nest"
	else
		current.Bar.Size = UDim2.new(0, 0, 1, 0)
		current.Tip.Text = ""
	end

	local canDeploy = deployment.Active and ownVehicle == nil and not actionBusy
	current.DeployFrame.Visible = canDeploy
	current.DeployValue.Text = "Deploy"
	setButtonEnabled(current.DeployButton, canDeploy)

	local hasOwnVehicle = ownVehicle ~= nil
	current.RecallFrame.Visible = hasOwnVehicle
	current.RecallValue.Text = "Recall"
	setButtonEnabled(
		current.RecallButton,
		hasOwnVehicle and ownVehicle.CanRecall ~= false and not actionBusy
	)
end

local function applyState(state)
	stateByNestId = {}
	if type(state) == "table" and type(state.Nests) == "table" then
		for _, snapshot in state.Nests do
			if type(snapshot) == "table" and type(snapshot.NestId) == "string" then
				stateByNestId[snapshot.NestId] = snapshot
			end
		end
	end
	applySelectedSnapshot()
end

local function refreshState(expectedPollingToken: number?)
	if not active or refreshInFlight then
		return
	end
	refreshInFlight = true
	local response = NestMapRemoteClient.GetState()
	refreshInFlight = false
	if not active
		or (expectedPollingToken ~= nil and expectedPollingToken ~= pollingToken)
	then
		return
	end
	if response.Succeeded and response.State then
		applyState(response.State)
	elseif not response.Succeeded then
		warn("巢穴 Map 状态获取失败：" .. tostring(response.Reason))
	end
end

local function beginPolling()
	pollingToken += 1
	local token = pollingToken
	task.spawn(function()
		while active and token == pollingToken do
			refreshState(token)
			task.wait(NestMapCameraConfigs.RefreshIntervalSeconds)
		end
	end)
end

local function focusSelectedNest()
	local nestId = getSelectedNestId()
	if not nestId then
		return
	end
	local nest, nestReason = NestMapSceneAccess.GetNest(nestId)
	local marker, markerReason = NestMapSceneAccess.GetCameraMarker(nestId)
	if not nest or not marker then
		warn(string.format(
			"巢穴 Map 镜头不可用：%s (%s/%s)",
			nestId,
			nestReason or "Unknown",
			markerReason or "Unknown"
		))
		return
	end
	local _, cameraReason = NestMapCameraController.Open(nest, marker)
	if cameraReason then
		warn(string.format("巢穴 Map 镜头切换失败：%s (%s)", nestId, cameraReason))
	end
end

local function moveSelection(delta: number)
	if not active then
		return
	end
	local count = #getDefinitions()
	if count <= 0 then
		return
	end
	selectedIndex = ((selectedIndex - 1 + delta) % count) + 1
	focusSelectedNest()
	local token = pollingToken
	task.spawn(function()
		refreshState(token)
	end)
end

local function applyActionResponse(response)
	if response.State then
		applyState(response.State)
	end
	if response.Succeeded then
		SoundController.Play("Yes")
	else
		if response.Reason ~= "RequestFailed"
			and response.Reason ~= "InvalidServerResponse"
			and response.Reason ~= "PlayerDataNotReady"
		then
			SoundController.Play("No")
		end
		warn("巢穴 Map 操作失败：" .. tostring(response.Reason))
	end
end

local function dispatchSelected()
	if actionBusy then
		return
	end
	local deployment = VehicleDeploymentState.Get()
	local nestId = getSelectedNestId()
	local snapshot = getSelectedSnapshot()
	if not deployment.Active or not deployment.VehicleInstanceId or not nestId then
		return
	end
	if snapshot and snapshot.OwnVehicle then
		return
	end

	actionBusy = true
	actionToken += 1
	local ownActionToken = actionToken
	applySelectedSnapshot()
	task.spawn(function()
		local response = NestMapRemoteClient.Dispatch(
			deployment.VehicleInstanceId :: string,
			nestId :: string
		)
		if not active or ownActionToken ~= actionToken then
			return
		end
		actionBusy = false
		if response.Succeeded then
			VehicleDeploymentState.Clear()
			if callbacks.OnVehicleStateChanged then
				callbacks.OnVehicleStateChanged()
			end
		end
		applyActionResponse(response)
	end)
end

local function recallSelected()
	if actionBusy then
		return
	end
	local snapshot = getSelectedSnapshot()
	local ownVehicle = snapshot and snapshot.OwnVehicle
	if not ownVehicle or ownVehicle.CanRecall == false then
		return
	end

	actionBusy = true
	actionToken += 1
	local ownActionToken = actionToken
	applySelectedSnapshot()
	task.spawn(function()
		local response = NestMapRemoteClient.Recall(ownVehicle.VehicleInstanceId)
		if not active or ownActionToken ~= actionToken then
			return
		end
		actionBusy = false
		if response.Succeeded and callbacks.OnVehicleStateChanged then
			callbacks.OnVehicleStateChanged()
		end
		applyActionResponse(response)
	end)
end

local function closeInternal(notifyStateChanged: boolean)
	local deploymentWasActive = VehicleDeploymentState.Get().Active
	active = false
	pollingToken += 1
	actionToken += 1
	actionBusy = false
	NestMapCameraController.Stop("NestMapClosed")
	VehicleDeploymentState.Clear()
	if visibilityGate then
		visibilityGate:SetDesiredVisible(false)
	end
	if notifyStateChanged
		and deploymentWasActive
		and callbacks.OnVehicleStateChanged
	then
		callbacks.OnVehicleStateChanged()
	end
end

local function exitMap()
	closeInternal(false)
	if callbacks.OnExit then
		callbacks.OnExit()
	end
end

function NestMapUIController.SetCallbacks(nextCallbacks: Callbacks)
	assert(type(nextCallbacks) == "table", "nextCallbacks 必须是 table")
	callbacks = {
		OnExit = nextCallbacks.OnExit,
		OnVehicleStateChanged = nextCallbacks.OnVehicleStateChanged,
	}
end

function NestMapUIController.Open()
	local current = references
	if not current then
		return
	end
	if active then
		applySelectedSnapshot()
		return
	end

	active = true
	actionBusy = false
	selectedIndex = getFirstIndex()
	if visibilityGate then
		visibilityGate:SetDesiredVisible(true)
	end
	applySelectedSnapshot()
	focusSelectedNest()
	beginPolling()
	local token = pollingToken
	task.spawn(function()
		refreshState(token)
	end)
end

function NestMapUIController.Close()
	closeInternal(true)
end

function NestMapUIController.Start()
	if started then
		return
	end
	started = true

	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local resolved, reason = resolveReferences(playerGui)
	if not resolved then
		warn("巢穴 Map UI 路径无效：" .. tostring(reason))
		return
	end
	references = resolved
	resolved.Root.Visible = false
	resolved.DeployFrame.Visible = false
	resolved.RecallFrame.Visible = false
	resolved.ProgressBar.Visible = false

	visibilityGate = LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Gameplay,
		function(nextVisible)
			if references then
				references.Root.Visible = nextVisible
			end
		end,
		false
	)

	resolved.LeftButton.Activated:Connect(function()
		moveSelection(-1)
	end)
	resolved.RightButton.Activated:Connect(function()
		moveSelection(1)
	end)
	resolved.DeployButton.Activated:Connect(dispatchSelected)
	resolved.RecallButton.Activated:Connect(recallSelected)
	resolved.ExitButton.Activated:Connect(exitMap)
end

return NestMapUIController
