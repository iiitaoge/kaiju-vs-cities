--[[
	职责：把玩家 Plot 的 Group 世界按钮接到 Main.Group 群组奖励面板。
	输入：Workspace/PlayerPlots/<OwnPlot>/Buttons/Group、PlayerGui.Main.Group、
	服务端 GroupRewardRequest RemoteFunction。
	输出：Group 按钮复用现有 WorldObjectUI 显示奖励和状态；踩 Group 打开面板；
	Verify.Button 请求服务端检查并领取；Close 隐藏面板；Unit3/Unit4 展示当前配置的两项奖励。
	内部算法：本地按钮触发 → 请求 GetState → 未领取时显示面板；点击 Verify 后由服务端
	再次检查群组成员身份、发放全部奖励并存档；成功后关闭面板并把世界按钮置为 Locked。
	不负责：判断群组成员、修改余额、发奖、存档或创建 UI。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalButtonController = require(script.Parent.Parent.Button.LocalButtonController)
local LocalPlotButtonAccess = require(script.Parent.Parent.Button.LocalPlotButtonAccess)
local LocalButtonWorldUIController = require(
	script.Parent.Parent.Button.LocalButtonWorldUIController
)
local LocalUIVisibilityGate = require(script.Parent.LocalUIVisibilityGate)
local LocalGuiButtonState = require(script.Parent.LocalGuiButtonState)
local TipBlackController = require(script.Parent.TipBlackController)
local CurrencyIconRenderer = require(script.Parent.CurrencyIconRenderer)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local LocalUIModeService = require(script.Parent.LocalUIModeService)
local GroupRewardConfigs = require(
	ReplicatedStorage.Shared.Reward.GroupRewardConfigs
)
local GroupRewardProtocol = require(
	ReplicatedStorage.Shared.Reward.GroupRewardProtocol
)
local SoundController = require(script.Parent.Parent.Sound.SoundController)

local GroupRewardUIController = {}

type ImageTarget = ImageLabel | ImageButton
type TextTarget = TextLabel | TextButton

type RewardSlotReferences = {
	Icon: ImageTarget,
	Info: TextTarget,
}

type References = {
	Root: GuiObject,
	VerifyButton: GuiButton,
	CloseButton: GuiButton,
	Slots: { [number]: RewardSlotReferences },
}

type RewardState = {
	Status: string,
	Available: boolean,
	IsMember: boolean,
	Claimed: boolean,
	GroupId: number,
	RewardId: string,
	Rewards: { [number]: { Type: string, Amount: number } },
}

type ServerResponse = {
	Succeeded: boolean,
	Reason: string?,
	State: RewardState?,
}

local localPlayer = Players.LocalPlayer
local references: References? = nil
local remote: RemoteFunction? = nil
local buttonHandle = nil
local worldUIHandle = nil
local visibilityGate = nil
local visible = false
local busy = false
local started = false

local SLOT_NAMES = table.freeze({ "Unit3", "Unit4" })

local function resolveChild(parent: Instance?, name: string): Instance?
	if not parent then
		return nil
	end
	return parent:FindFirstChild(name)
end

local function resolveGuiObject(parent: Instance?, name: string): GuiObject?
	local child = resolveChild(parent, name)
	if child and child:IsA("GuiObject") then
		return child
	end
	return nil
end

local function resolveButton(parent: Instance?, name: string): GuiButton?
	local child = resolveChild(parent, name)
	if child and child:IsA("GuiButton") then
		return child
	end
	return nil
end

local function resolveImageTarget(parent: Instance?, name: string): ImageTarget?
	local child = resolveChild(parent, name)
	if child and (child:IsA("ImageLabel") or child:IsA("ImageButton")) then
		return child :: ImageTarget
	end
	return nil
end

local function resolveTextTarget(parent: Instance?, name: string): TextTarget?
	local child = resolveChild(parent, name)
	if child and (child:IsA("TextLabel") or child:IsA("TextButton")) then
		return child :: TextTarget
	end
	return nil
end

local function resolveSlot(parent: Instance?, slotName: string): (RewardSlotReferences?, string?)
	local slot = resolveGuiObject(parent, slotName)
	local icon = resolveImageTarget(slot, "Icon")
	local info = resolveTextTarget(slot, "Info")
	if not slot then
		return nil, slotName .. "Unavailable"
	end
	if not icon then
		return nil, slotName .. "IconUnavailable"
	end
	if not info then
		return nil, slotName .. "InfoUnavailable"
	end
	return { Icon = icon, Info = info }, nil
end

local function resolveReferences(playerGui: PlayerGui): (References?, string?)
	local mainGui = playerGui:FindFirstChild("Main")
	if not mainGui or not mainGui:IsA("ScreenGui") then
		return nil, "MainGuiUnavailable"
	end

	local group = resolveGuiObject(mainGui, "Group")
	local mainAll = resolveGuiObject(group, "MainAll")
	local title = resolveGuiObject(mainAll, "Title")
	local main = resolveGuiObject(mainAll, "Main")
	local verify = resolveGuiObject(main, "Verify")
	local verifyButton = resolveButton(verify, "Button")
	local closeButton = resolveButton(title, "Close")
	if not group then
		return nil, "GroupUnavailable"
	end
	if not mainAll then
		return nil, "MainAllUnavailable"
	end
	if not title then
		return nil, "TitleUnavailable"
	end
	if not main then
		return nil, "MainUnavailable"
	end
	if not verify then
		return nil, "VerifyUnavailable"
	end
	if not verifyButton then
		return nil, "VerifyButtonUnavailable"
	end
	if not closeButton then
		return nil, "CloseUnavailable"
	end

	local slots: { [number]: RewardSlotReferences } = {}
	for index, slotName in SLOT_NAMES do
		local slot, reason = resolveSlot(main, slotName)
		if not slot then
			return nil, reason
		end
		slots[index] = slot
	end

	return {
		Root = group,
		VerifyButton = verifyButton,
		CloseButton = closeButton,
		Slots = slots,
	}, nil
end

local function resolveRemote(): RemoteFunction?
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local candidate = remotes and remotes:WaitForChild(
		GroupRewardProtocol.RemoteName,
		10
	)
	if candidate and candidate:IsA("RemoteFunction") then
		return candidate
	end
	return nil
end

local function formatRewardAmount(amount: number): string
	return tostring(amount)
end

local function renderConfiguredRewards()
	local current = references
	if not current then
		return
	end

	for index, slot in current.Slots do
		local reward = GroupRewardConfigs.Rewards[index]
		if reward then
			CurrencyIconRenderer.Apply(slot.Icon, reward.Type)
			slot.Info.Text = formatRewardAmount(reward.Amount)
		else
			slot.Icon.Visible = false
			slot.Info.Text = ""
		end
	end
end

local function formatWorldReward(reward): string
	local label = if reward.Type == GroupRewardProtocol.Types.Money
		then "Money"
		elseif reward.Type == GroupRewardProtocol.Types.Diamond
		then "Diamond"
		else tostring(reward.Type)
	return string.format("%s +%s", label, tostring(reward.Amount))
end

local function setWorldPresentation(state: RewardState?)
	local firstReward = GroupRewardConfigs.Rewards[1]
	local secondReward = GroupRewardConfigs.Rewards[2]
	local statusText = if not state
		then "Check"
		elseif state.Claimed
		then "Claimed"
		elseif state.IsMember
		then "Claim"
		else "Join Group"
	local presentation = {
		Enabled = true,
		Texts = {
			Text1 = { Visible = true, Text = "Group Reward" },
			Text2 = {
				Visible = firstReward ~= nil,
				Text = if firstReward then formatWorldReward(firstReward) else "",
			},
			Text3 = {
				Visible = secondReward ~= nil,
				Text = if secondReward then formatWorldReward(secondReward) else "",
			},
			Text4 = { Visible = true, Text = statusText },
			Text5 = { Visible = false, Text = "" },
		},
		Money = { Visible = false, Text = "" },
	}
	if worldUIHandle then
		worldUIHandle:SetPresentation(presentation)
	end
	if buttonHandle then
		buttonHandle:SetState(if state then (if state.Claimed then "Locked" else "Ready") else "Processing")
		buttonHandle:RefreshTouching()
	end
end

local function setVerifyEnabled(enabled: boolean)
	local current = references
	if not current then
		return
	end
	LocalGuiButtonState.SetEnabled(current.VerifyButton, enabled)
end

local function renderState(state: RewardState)
	local current = references
	if not current then
		return
	end
	setVerifyEnabled(not busy and not state.Claimed)
	if state.Claimed then
		current.Root.Visible = false
		visible = false
		if visibilityGate then
			visibilityGate:SetDesiredVisible(false)
		end
		if buttonHandle then
			buttonHandle:SetState("Locked")
		end
	end
	setWorldPresentation(state)
end

local function setVisible(nextVisible: boolean)
	visible = nextVisible
	if visibilityGate then
		visibilityGate:SetDesiredVisible(nextVisible)
	elseif references then
		references.Root.Visible = nextVisible
	end
end

local function invoke(requestKind: string): ServerResponse?
	local currentRemote = remote
	if not currentRemote then
		return nil
	end

	local succeeded, response = pcall(function()
		return currentRemote:InvokeServer(requestKind)
	end)
	if not succeeded or type(response) ~= "table" then
		warn("群组奖励 UI 请求失败：" .. tostring(response))
		return nil
	end
	return response :: ServerResponse
end

local function refreshState(): RewardState?
	local response = invoke(GroupRewardProtocol.RequestKinds.GetState)
	if not response then
		return nil
	end
	if response.State then
		renderState(response.State)
	end
	if not response.Succeeded then
		warn("群组奖励状态不可用：" .. tostring(response.Reason))
		return nil
	end
	return response.State
end

local function openPanel()
	if visible or busy then
		return
	end

	local state = refreshState()
	if not state then
		return
	end
	if state.Claimed then
		return
	end

	renderConfiguredRewards()
	setVisible(true)
end

local function verify()
	if busy or not visible then
		return
	end

	busy = true
	setVerifyEnabled(false)
	local response = invoke(GroupRewardProtocol.RequestKinds.Claim)
	busy = false
	if not response then
		TipBlackController.ShowMessage("Group reward request failed. Please try again later.")
		setVerifyEnabled(true)
		return
	end
	if response.State then
		renderState(response.State)
	end

	if response.Succeeded then
		SoundController.Play("Yes")
		TipBlackController.ShowMessage("Group reward claimed!")
		setVisible(false)
		if buttonHandle then
			buttonHandle:SetState("Locked")
		end
		return
	end
	if response.Reason ~= GroupRewardProtocol.Reasons.PlayerDataNotReady then
		SoundController.Play("No")
	end

	if response.Reason == GroupRewardProtocol.Reasons.NotGroupMember then
		TipBlackController.ShowMessage("Join the group before claiming this reward.")
	elseif response.Reason == GroupRewardProtocol.Reasons.RewardAlreadyClaimed then
		TipBlackController.ShowMessage("This group reward has already been claimed.")
	elseif response.Reason == GroupRewardProtocol.Reasons.GroupCheckFailed then
		TipBlackController.ShowMessage("Group status check failed. Please try again later.")
	elseif response.Reason == GroupRewardProtocol.Reasons.PlayerDataNotReady then
		TipBlackController.ShowMessage("Player data is still loading. Please try again.")
	else
		TipBlackController.ShowMessage("This group reward is temporarily unavailable. Please try again later.")
	end
	if response.State then
		setVerifyEnabled(not response.State.Claimed)
	end
end

function GroupRewardUIController.Start()
	if started then
		return
	end
	started = true

	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	playerGui:WaitForChild("Main", 10)
	local resolved, reason = resolveReferences(playerGui)
	if not resolved then
		warn("群组奖励 UI 路径无效：" .. tostring(reason))
		return
	end
	references = resolved
	resolved.Root.Visible = false
	renderConfiguredRewards()

	visibilityGate = LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Gameplay,
		function(nextVisible)
			if references then
				references.Root.Visible = nextVisible
			end
		end,
		false
	)

	remote = resolveRemote()
	if not remote then
		warn("群组奖励 RemoteFunction 不存在：" .. GroupRewardProtocol.RemoteName)
		return
	end

	local groupButton = LocalPlotButtonAccess.WaitForRoot(
		localPlayer.UserId,
		"Group",
		10
	)
	if not groupButton then
		warn("玩家 Plot 的 Group 按钮不可用")
		return
	end

	buttonHandle = LocalButtonController.Bind(groupButton, function()
		if not visible and not busy then
			SoundController.Play("Click")
		end
		openPanel()
	end)
	worldUIHandle = LocalButtonWorldUIController.Bind(groupButton)
	setWorldPresentation(nil)
	LocalUIModeService.Observe(function()
		if buttonHandle then
			buttonHandle:SetInputEnabled(LocalUIModeService.IsAllowed(
				UIModeVisibilityRules.Channels.Gameplay
			))
		end
	end)
	task.spawn(refreshState)

	resolved.CloseButton.Activated:Connect(function()
		setVisible(false)
	end)
	resolved.VerifyButton.Activated:Connect(verify)
end

return GroupRewardUIController
