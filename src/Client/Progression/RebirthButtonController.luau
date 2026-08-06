--[[
	职责：让玩家踩到所属 Plot 的重生按钮时显示本地 UI，并只通过 UI 点击请求重生。
	输入：玩家 Plot 下的 Rebirth-Button 场景合同和服务器状态快照。
	输出：本地 BillboardGui 显隐、文本更新和 Execute Remote 请求。
	内部算法：追踪本地角色触碰 → 周期刷新状态；UI Button.Activated 才执行重生。
	不负责：物理按钮下压动画、资格、距离授权、存档或运行时重载。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnalyticsIntentClient = require(script.Parent.Parent.Analytics.AnalyticsIntentClient)
local LocalRebirthButtonAccess = require(script.Parent.LocalRebirthButtonAccess)
local LocalPlotButtonAccess = require(script.Parent.Parent.Button.LocalPlotButtonAccess)
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
local AnalyticsIntentProtocol = require(
	ReplicatedStorage.Shared.Analytics.AnalyticsIntentProtocol
)

local RebirthButtonController = {}

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
	if ui.Billboard.Adornee == nil then
		ui.Billboard.Adornee = ui.Pull
	end
	placeBillboardAboveButton(button, ui.Pull, ui.Billboard)
	ui.Billboard.Enabled = false
	local visibilityGate = LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Gameplay,
		function(nextVisible)
			ui.Billboard.Enabled = nextVisible
		end,
		false
	)
	ui.MoneyButton.Active = false
	ui.MoneyButton.Selectable = false

	local touchingParts: { [BasePart]: boolean } = {}
	local visible = false
	local busy = false
	local refreshGeneration = 0
	local lastSnapshot = nil

	local function applySnapshot(snapshot)
		lastSnapshot = snapshot
		local presentation = RebirthUIPresentationRules.Resolve(snapshot)
		if not presentation.Enabled then
			ui.ActionButton.Active = false
			ui.ActionValue.Text = "Unavailable"
			return
		end
		ui.TitleLabel.Text = presentation.TitleText
		ui.ActionValue.Text = presentation.ActionText
		ui.ActionTip.Text = presentation.TipText
		ui.RequirementValue.Text = presentation.RequirementText
		ui.InfoTitle.Text = presentation.InfoTitleText
		ui.Introduction.Text = presentation.IntroductionText
		ui.ActionButton.Active = presentation.CanExecute and not busy
		ui.ActionButton.Selectable = presentation.CanExecute and not busy
	end

	local function request(requestKind: string)
		local succeeded, snapshot, reason = pcall(
			remote.InvokeServer,
			remote,
			requestKind
		)
		if not succeeded then
			warn("重生请求失败：" .. tostring(snapshot))
			return nil
		end
		if reason then
			warn("重生请求被拒绝：" .. tostring(reason))
		end
		return snapshot
	end

	local function refresh()
		if not visible or busy then
			return
		end
		local snapshot = request("GetState")
		if snapshot then
			applySnapshot(snapshot)
		end
	end

	local function setVisible(nextVisible: boolean)
		if visible == nextVisible then
			return
		end
		visible = nextVisible
		refreshGeneration += 1
		visibilityGate:SetDesiredVisible(visible)
		if not visible then
			return
		end
		AnalyticsIntentClient.Record(
			AnalyticsIntentProtocol.Intents.RebirthOpened
		)

		local generation = refreshGeneration
		task.spawn(function()
			refresh()
			while visible and generation == refreshGeneration do
				task.wait(RebirthProgressionConfigs.Button.RefreshIntervalSeconds)
				refresh()
			end
		end)
	end

	local function belongsToLocalCharacter(part: BasePart): boolean
		local character = Players.LocalPlayer.Character
		return character ~= nil and part:IsDescendantOf(character)
	end

	ui.Pull.Touched:Connect(function(part)
		if belongsToLocalCharacter(part) then
			touchingParts[part] = true
			setVisible(true)
		end
	end)
	ui.Pull.TouchEnded:Connect(function(part)
		if touchingParts[part] then
			touchingParts[part] = nil
			setVisible(next(touchingParts) ~= nil)
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		table.clear(touchingParts)
		setVisible(false)
	end)

	ui.ActionButton.Activated:Connect(function()
		if busy or not visible then
			return
		end
		local presentation = RebirthUIPresentationRules.Resolve(lastSnapshot)
		if not presentation.CanExecute then
			return
		end

		busy = true
		AnalyticsIntentClient.Record(
			AnalyticsIntentProtocol.Intents.RebirthExecuteClicked
		)
		ui.ActionButton.Active = false
		ui.ActionButton.Selectable = false
		ui.ActionValue.Text = "Processing..."
		local snapshot = request("Execute")
		busy = false
		if snapshot then
			applySnapshot(snapshot)
		else
			refresh()
		end
	end)
end

return RebirthButtonController
