--[[
	职责：把七日奖励配置和服务器状态展示到 Main.Check，并发送领取请求。
	输入：PlayerGui.Main.Check、ReplicatedStorage 中的奖励 RemoteFunction、七日奖励配置和货币图标数据树。
	输出：新手引导完成提示结束后自动显示七日奖励面板；七张奖励卡的图标/数值/可用状态、关闭按钮行为，
	以及成功领取后的最新 UI 状态。
	内部算法：启动时先读取所有配置并向服务器请求当前状态，等待引导完成提示结束后显示面板；已领取档位变暗且不可点击，
	其余档位保持可点击；点击当前可领取档位发送领取请求，点击其他未领取档位显示英文等待提示，并在本地冷却结束时重新同步一次。
	不负责：计算奖励、判断冷却、修改货币、创建存档或创建整套 UI。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyIconRenderer = require(script.Parent.CurrencyIconRenderer)
local SevenDayRewardConfigs = require(
	ReplicatedStorage.Shared.Reward.SevenDayRewardConfigs
)
local SevenDayRewardProtocol = require(
	ReplicatedStorage.Shared.Reward.SevenDayRewardProtocol
)
local SoundController = require(script.Parent.Parent.Sound.SoundController)
local TipBlackController = require(script.Parent.TipBlackController)
local LocalGuiButtonState = require(script.Parent.LocalGuiButtonState)
local LocalUIVisibilityGate = require(script.Parent.LocalUIVisibilityGate)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local TutorialController = require(script.Parent.Parent.Tutorial.TutorialController)

local SevenDayRewardUIController = {}

type DayCardReferences = {
	Button: GuiButton,
	Icon: ImageLabel,
	BackgroundImage: ImageLabel?,
	Day: TextLabel,
	Value: TextLabel,
	Tip: TextLabel?,
	BaseButtonBackgroundColor: Color3,
	BaseBackgroundImageColor: Color3?,
	BaseIconColor: Color3,
	BaseDayTextColor: Color3,
	BaseValueTextColor: Color3,
	BaseTipTextColor: Color3?,
}

type References = {
	Root: GuiObject,
	CloseButton: GuiButton,
	Cards: { [number]: DayCardReferences },
}

type RewardState = {
	Status: string,
	Day: number,
	Available: boolean,
	NextClaimAt: number,
	RemainingSeconds: number,
	Reward: { Day: number, Type: string, Amount: number }?,
}

type ServerResponse = {
	Succeeded: boolean,
	Reason: string?,
	State: RewardState?,
}

local localPlayer = Players.LocalPlayer
local references: References? = nil
local remote: RemoteFunction? = nil
local currentState: RewardState? = nil
local stateReceivedServerTime = 0
local claimInFlight = false
local started = false
local visibilityGate: LocalUIVisibilityGate.Handle? = nil

local function darkenColor(color: Color3): Color3
	return color:Lerp(Color3.new(0, 0, 0), 0.55)
end

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

local function resolveTextLabel(parent: Instance?, name: string): TextLabel?
	local child = resolveChild(parent, name)
	if child and child:IsA("TextLabel") then
		return child
	end
	return nil
end

local function resolveImageLabel(parent: Instance?, name: string): ImageLabel?
	local child = resolveChild(parent, name)
	if child and child:IsA("ImageLabel") then
		return child
	end
	return nil
end

local function resolveCard(dayFrame: Instance?, day: number): (DayCardReferences?, string?)
	local button = resolveButton(dayFrame, "Button")
	local icon = resolveImageLabel(button, "Icon")
	local backgroundImage = resolveImageLabel(button, "BG")
	local dayLabel = resolveTextLabel(button, "Day")
	local valueLabel = resolveTextLabel(button, "Val")
	local tipLabel = resolveTextLabel(button, "Tip")

	if not dayFrame then
		return nil, string.format("Day%dUnavailable", day)
	end
	if not button then
		return nil, string.format("Day%dButtonUnavailable", day)
	end
	if not icon then
		return nil, string.format("Day%dIconUnavailable", day)
	end
	if not dayLabel then
		return nil, string.format("Day%dLabelUnavailable", day)
	end
	if not valueLabel then
		return nil, string.format("Day%dValueUnavailable", day)
	end

	return {
		Button = button,
		Icon = icon,
		BackgroundImage = backgroundImage,
		Day = dayLabel,
		Value = valueLabel,
		Tip = tipLabel,
		BaseButtonBackgroundColor = button.BackgroundColor3,
		BaseBackgroundImageColor = if backgroundImage
			then backgroundImage.ImageColor3
			else nil,
		BaseIconColor = icon.ImageColor3,
		BaseDayTextColor = dayLabel.TextColor3,
		BaseValueTextColor = valueLabel.TextColor3,
		BaseTipTextColor = if tipLabel then tipLabel.TextColor3 else nil,
	}, nil
end

local function resolveReferences(playerGui: PlayerGui): (References?, string?)
	local mainGui = playerGui:FindFirstChild("Main")
	if not mainGui or not mainGui:IsA("ScreenGui") then
		return nil, "MainGuiUnavailable"
	end

	local check = resolveGuiObject(mainGui, "Check")
	local mainAll = resolveGuiObject(check, "MainAll")
	local title = resolveGuiObject(mainAll, "Title")
	local main = resolveGuiObject(mainAll, "Main")
	local six = resolveGuiObject(main, "Six")
	local seven = resolveGuiObject(main, "Seven")
	local closeButton = resolveButton(title, "Close")

	if not check then
		return nil, "CheckUnavailable"
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
	if not six then
		return nil, "SixUnavailable"
	end
	if not seven then
		return nil, "SevenUnavailable"
	end
	if not closeButton then
		return nil, "CloseUnavailable"
	end

	local cards: { [number]: DayCardReferences } = {}
	for day = 1, 6 do
		local dayFrame = resolveGuiObject(six, string.format("Day%d", day))
		local card, reason = resolveCard(dayFrame, day)
		if not card then
			return nil, reason
		end
		cards[day] = card
	end
	local daySevenCard, reason = resolveCard(seven, 7)
	if not daySevenCard then
		return nil, reason
	end
	cards[7] = daySevenCard

	return {
		Root = check,
		CloseButton = closeButton,
		Cards = cards,
	}, nil
end

local function resolveRemote(): RemoteFunction?
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local candidate = remotes and remotes:WaitForChild(
		SevenDayRewardProtocol.RemoteName,
		10
	)
	if candidate and candidate:IsA("RemoteFunction") then
		return candidate
	end
	return nil
end

local function renderConfiguredRewards()
	local current = references
	if not current then
		return
	end

	for day = 1, SevenDayRewardConfigs.TotalDays do
		local reward = SevenDayRewardConfigs.Days[day]
		local card = current.Cards[day]
		if reward and card then
			card.Day.Text = string.format("Day %d", day)
			card.Value.Text = tostring(reward.Amount)
			CurrencyIconRenderer.Apply(card.Icon, reward.Type)
			card.BaseIconColor = card.Icon.ImageColor3
		end
	end
end

local function secondsSinceStateReceived(): number
	return math.max(
		0,
		math.floor(workspace:GetServerTimeNow() - stateReceivedServerTime)
	)
end

local function formatDuration(totalSeconds: number): string
	local seconds = math.max(0, math.floor(totalSeconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local remainder = seconds % 60
	return string.format("%02d:%02d:%02d", hours, minutes, remainder)
end

local function showUnavailableMessage(day: number, state: RewardState)
	if state.Status == SevenDayRewardProtocol.Statuses.Cooldown then
		SoundController.Play("No")
		local localRemaining = math.max(
			0,
			state.RemainingSeconds - secondsSinceStateReceived()
		)
		local daysAhead = math.max(0, day - state.Day)
		local earliestRemaining = localRemaining
			+ daysAhead * SevenDayRewardConfigs.CooldownSeconds
		if daysAhead == 0 then
			TipBlackController.ShowMessage(
				string.format("Reward available in %s.", formatDuration(earliestRemaining))
			)
		else
			TipBlackController.ShowMessage(
				string.format(
					"Reward available after claiming Day %d. Earliest in %s.",
					state.Day,
					formatDuration(earliestRemaining)
				)
			)
		end
		return
	end

	if state.Status == SevenDayRewardProtocol.Statuses.Claimable and day > state.Day then
		SoundController.Play("No")
		local earliestRemaining = (day - state.Day)
			* SevenDayRewardConfigs.CooldownSeconds
		TipBlackController.ShowMessage(
			string.format(
				"Claim Day %d first. Earliest in %s.",
				state.Day,
				formatDuration(earliestRemaining)
			)
		)
	end
end

local function setCardEnabled(card: DayCardReferences, enabled: boolean)
	LocalGuiButtonState.SetEnabled(card.Button, enabled)
end

local function setCardCompleted(card: DayCardReferences, completed: boolean)
	if completed then
		card.Button.BackgroundColor3 = darkenColor(
			card.BaseButtonBackgroundColor
		)
		if card.BackgroundImage and card.BaseBackgroundImageColor then
			card.BackgroundImage.ImageColor3 = darkenColor(
				card.BaseBackgroundImageColor
			)
		end
		card.Icon.ImageColor3 = darkenColor(card.BaseIconColor)
		card.Day.TextColor3 = darkenColor(card.BaseDayTextColor)
		card.Value.TextColor3 = darkenColor(card.BaseValueTextColor)
		if card.Tip and card.BaseTipTextColor then
			card.Tip.TextColor3 = darkenColor(card.BaseTipTextColor)
		end
		return
	end

	card.Button.BackgroundColor3 = card.BaseButtonBackgroundColor
	if card.BackgroundImage and card.BaseBackgroundImageColor then
		card.BackgroundImage.ImageColor3 = card.BaseBackgroundImageColor
	end
	card.Icon.ImageColor3 = card.BaseIconColor
	card.Day.TextColor3 = card.BaseDayTextColor
	card.Value.TextColor3 = card.BaseValueTextColor
	if card.Tip and card.BaseTipTextColor then
		card.Tip.TextColor3 = card.BaseTipTextColor
	end
end

local function renderState(state: RewardState)
	local current = references
	if not current then
		return
	end

	currentState = state
	stateReceivedServerTime = workspace:GetServerTimeNow()
	for day = 1, SevenDayRewardConfigs.TotalDays do
		local card = current.Cards[day]
		local completed = day < state.Day
		setCardEnabled(card, not completed and not claimInFlight)
		setCardCompleted(card, completed)
	end
end

local function refreshCardInteractivity()
	local current = references
	local state = currentState
	if not current then
		return
	end
	for day = 1, SevenDayRewardConfigs.TotalDays do
		local completed = state ~= nil and day < state.Day
		setCardEnabled(current.Cards[day], not claimInFlight and not completed)
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
		warn("七日奖励 UI 请求失败：" .. tostring(response))
		return nil
	end
	return response :: ServerResponse
end

local function refreshState()
	local response = invoke(SevenDayRewardProtocol.RequestKinds.GetState)
	if not response then
		return
	end
	if response.State then
		renderState(response.State)
	end
	if not response.Succeeded then
		warn("七日奖励状态不可用：" .. tostring(response.Reason))
		if response.Reason == SevenDayRewardProtocol.Reasons.PlayerDataNotReady then
			task.delay(1, function()
				if started then
					refreshState()
				end
			end)
		end
	end
end

local function claim(day: number)
	if claimInFlight then
		return
	end

	local state = currentState
	if not state or day < state.Day then
		return
	end

	if state.Status ~= SevenDayRewardProtocol.Statuses.Claimable
		or not state.Available
		or state.Day ~= day
	then
		showUnavailableMessage(day, state)
		return
	end

	claimInFlight = true
	refreshCardInteractivity()
	local response = invoke(SevenDayRewardProtocol.RequestKinds.Claim)
	claimInFlight = false
	if not response then
		refreshCardInteractivity()
		return
	end
	if response.State then
		renderState(response.State)
	end
	if response.Succeeded then
		SoundController.Play("Yes")
	elseif response.Reason ~= SevenDayRewardProtocol.Reasons.PlayerDataNotReady then
		SoundController.Play("No")
		warn("七日奖励领取失败：" .. tostring(response.Reason))
	end
end

local function refreshWhenCooldownEnds()
	while started do
		task.wait(1)
		local state = currentState
		if state
			and state.Status == SevenDayRewardProtocol.Statuses.Cooldown
			and state.RemainingSeconds - secondsSinceStateReceived() <= 0
		then
			refreshState()
		end
	end
end

function SevenDayRewardUIController.Start()
	if started then
		return
	end
	started = true

	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	playerGui:WaitForChild("Main", 10)
	local resolved, reason = resolveReferences(playerGui)
	if not resolved then
		warn("七日奖励 UI 路径无效：" .. tostring(reason))
		return
	end
	references = resolved
	-- 新手引导完成提示结束后自动弹出；关闭按钮只影响本次客户端会话。
	resolved.Root.Visible = false
	visibilityGate = LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Gameplay,
		function(visible)
			if references then
				references.Root.Visible = visible
			end
		end,
		false
	)
	refreshCardInteractivity()

	remote = resolveRemote()
	if not remote then
		warn("七日奖励 RemoteFunction 不存在：" .. SevenDayRewardProtocol.RemoteName)
		return
	end
	resolved.CloseButton.Activated:Connect(function()
		if visibilityGate then
			visibilityGate:SetDesiredVisible(false)
		end
	end)
	for day = 1, SevenDayRewardConfigs.TotalDays do
		local card = resolved.Cards[day]
		card.Button.Activated:Connect(function()
			claim(day)
		end)
	end

	renderConfiguredRewards()
	refreshState()
	task.spawn(refreshWhenCooldownEnds)
	task.spawn(function()
		TutorialController.WaitUntilComplete()
		if started and visibilityGate then
			visibilityGate:SetDesiredVisible(true)
		end
	end)
end

return SevenDayRewardUIController
