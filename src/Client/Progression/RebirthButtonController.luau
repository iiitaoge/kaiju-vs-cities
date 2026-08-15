--[[
	职责：让所属 Plot 的新重生 UI 始终可见，并把操作按钮接入重生请求。
	输入：玩家 Plot 下的 Rebirth-Button 场景合同和服务器状态快照。
	输出：以 Pull 为 Adornee 的本地 BillboardGui、按钮反馈、实体按钮动画和 Execute Remote 请求。
	内部算法：由 LocalRebirthButtonAccess 克隆 ReplicatedStorage.UI.Rebith，放入本地 PlayerGui；周期刷新服务器快照；
	实体 Pull 只播放已有下压动画，不绕过服务器资格校验。
	不负责：金额资格、距离授权、存档或重生规则。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsIntentClient = require(script.Parent.Parent.Analytics.AnalyticsIntentClient)
local LocalRebirthButtonAccess = require(script.Parent.LocalRebirthButtonAccess)
local LocalPlotButtonAccess = require(script.Parent.Parent.Button.LocalPlotButtonAccess)
local LocalButtonController = require(script.Parent.Parent.Button.LocalButtonController)
local RebirthProgressionConfigs = require(
	ReplicatedStorage.Shared.Progression.RebirthProgressionConfigs
)
local RebirthProtocol = require(
	ReplicatedStorage.Shared.Progression.RebirthProtocol
)
local RebirthUIPresentationRules = require(
	ReplicatedStorage.Shared.UI.RebirthUIPresentationRules
)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local LocalUIVisibilityGate = require(
	script.Parent.Parent.UI.LocalUIVisibilityGate
)
local LocalGuiButtonState = require(
	script.Parent.Parent.UI.LocalGuiButtonState
)
local SoundController = require(script.Parent.Parent.Sound.SoundController)
local AnalyticsIntentProtocol = require(
	ReplicatedStorage.Shared.Analytics.AnalyticsIntentProtocol
)

local RebirthButtonController = {}

local function configureInformationLayout(ui, showInfoTitle: boolean)
	-- 标题隐藏时，说明区域占满标题与操作按钮之间的可用空间。
	-- 全部使用模板坐标系中的比例，保持 Billboard 在不同屏幕上的布局一致。
	if ui.BuyIcon then
		ui.BuyIcon.Visible = false
	end
	ui.InfoTitle.Visible = showInfoTitle
	if showInfoTitle then
		ui.Introduction.Position = UDim2.fromScale(0.5, 0.2)
		ui.Introduction.Size = UDim2.fromScale(0.95, 0.5)
		ui.Introduction.TextYAlignment = Enum.TextYAlignment.Center
		return
	end
	ui.Introduction.Position = UDim2.fromScale(0.5, 0.02)
	ui.Introduction.Size = UDim2.fromScale(0.95, 0.7)
	ui.Introduction.TextYAlignment = Enum.TextYAlignment.Top
end

-- 输入：按钮世界包围盒、UI 锚点零件及 Billboard 的世界尺寸。
-- 输出：BillboardGui 的世界偏移，使 UI 底边位于按钮顶面上方。
local function placeBillboardAboveButton(
	button: Model,
	pull: BasePart,
	billboard: BillboardGui
)
	local boundsCFrame, boundsSize = button:GetBoundingBox()
	local buttonTopY = boundsCFrame.Position.Y + boundsSize.Y * 0.5
	local billboardHalfHeight = math.max(billboard.Size.Y.Scale, 0) * 0.5
	local targetCenterY = buttonTopY
		+ billboardHalfHeight
		+ RebirthProgressionConfigs.Button.UIBottomClearanceStuds
	local currentOffset = billboard.StudsOffsetWorldSpace
	billboard.StudsOffsetWorldSpace = Vector3.new(
		currentOffset.X,
		targetCenterY - pull.Position.Y,
		currentOffset.Z
	)
end

-- 输入：Workspace 中的 BillboardGui。
-- 输出：可由本地鼠标命中的 PlayerGui BillboardGui。
-- 内部算法：保留 Adornee 的世界投影，只改变 GUI 容器；打开顶层渲染和输入。
local function attachBillboardToLocalPlayerGui(billboard: BillboardGui)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	billboard.ResetOnSpawn = false
	billboard.Active = true
	billboard.AlwaysOnTop = true
	billboard.Parent = playerGui
end

local function waitForRemote(): RemoteFunction?
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local remote = remotes and remotes:WaitForChild(RebirthProtocol.RemoteName, 10)
	if not remote or not remote:IsA("RemoteFunction") then
		warn("重生 RemoteFunction 不可用")
		return nil
	end
	return remote
end

local function waitForButton(): Model?
	local button = LocalPlotButtonAccess.WaitForRoot(
		Players.LocalPlayer.UserId,
		RebirthProgressionConfigs.Button.ButtonName,
		10
	)
	if not button then
		warn("玩家 Plot 的重生按钮不可用：" .. RebirthProgressionConfigs.Button.ButtonName)
		return nil
	end
	return button
end

function RebirthButtonController.Start()
	local remote = waitForRemote()
	local button = waitForButton()
	if not remote or not button then
		return
	end

	local ui = LocalRebirthButtonAccess.Resolve(button)
	configureInformationLayout(ui, false)
	ui.Billboard.Adornee = ui.Pull
	placeBillboardAboveButton(button, ui.Pull, ui.Billboard)
	attachBillboardToLocalPlayerGui(ui.Billboard)
	ui.Billboard.Enabled = true
	local visibilityGate = LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Gameplay,
		function(nextVisible)
			ui.Billboard.Enabled = nextVisible
		end,
		true
	)

	local physicalButton = LocalButtonController.Bind(button)
	local visible = true
	local busy = false
	local lastSnapshot = nil

	local function setGuiButtonsEnabled(enabled: boolean)
		LocalGuiButtonState.SetEnabled(ui.ActionButton, enabled)
	end

	setGuiButtonsEnabled(true)

	local function setPhysicalButtonState(status: string?)
		local state = if status == "Ready"
			then "Ready"
			elseif status == "Insufficient"
			then "Insufficient"
			elseif status == "Processing"
			then "Processing"
			else "Locked"
		physicalButton:SetState(state)
	end

	local function applySnapshot(snapshot)
		lastSnapshot = snapshot
		local presentation = RebirthUIPresentationRules.Resolve(snapshot)
		if not presentation.Enabled then
			setGuiButtonsEnabled(not busy)
			setPhysicalButtonState(nil)
			ui.ActionValue.Text = "Unavailable"
			return
		end
		ui.TitleLabel.Text = presentation.TitleText
		ui.ActionValue.Text = presentation.ActionText
		ui.ActionTip.Text = presentation.TipText
		ui.RequirementValue.Text = presentation.RequirementText
		ui.InfoTitle.Text = presentation.InfoTitleText
		ui.Introduction.Text = presentation.IntroductionText
		configureInformationLayout(ui, presentation.InfoTitleText ~= "")
		setGuiButtonsEnabled(not busy)
		setPhysicalButtonState(snapshot.Status)
	end

	local function request(requestKind: string)
		local succeeded, snapshot, reason, actionSucceeded = pcall(
			remote.InvokeServer,
			remote,
			requestKind
		)
		if not succeeded then
			warn("重生请求失败：" .. tostring(snapshot))
			return nil, "RequestFailed", false
		end
		if reason then
			warn("重生请求被拒绝：" .. tostring(reason))
		end
		return snapshot, reason, actionSucceeded
	end

	local function refresh()
		if busy then
			return
		end
		local snapshot = request("GetState")
		if snapshot then
			applySnapshot(snapshot)
		end
	end

	local function executeRebirth()
		if busy or not visible then
			return
		end

		busy = true
		AnalyticsIntentClient.Record(
			AnalyticsIntentProtocol.Intents.RebirthExecuteClicked
		)
		setGuiButtonsEnabled(false)
		ui.ActionValue.Text = "Processing..."
		local snapshot, reason, actionSucceeded = request("Execute")
		if actionSucceeded == true then
			SoundController.Play("Yes")
		elseif reason
			and reason ~= "PlayerDataNotReady"
			and reason ~= "RequestFailed"
		then
			SoundController.Play("No")
		end
		busy = false
		if snapshot then
			applySnapshot(snapshot)
		else
			refresh()
		end
	end

	ui.ActionButton.Activated:Connect(executeRebirth)

	SoundController.Play("Click")
	AnalyticsIntentClient.Record(
		AnalyticsIntentProtocol.Intents.RebirthOpened
	)
	task.spawn(function()
		while Players.LocalPlayer.Parent and ui.Billboard.Parent do
			refresh()
			task.wait(RebirthProgressionConfigs.Button.RefreshIntervalSeconds)
		end
	end)
end

return RebirthButtonController
