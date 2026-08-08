--[[
	职责：使用 Main/lottery 播放服务端已经结算完成的载具开奖演出。
	输入：按抽取顺序排列的奖励列表，每项包含 VehicleId、Name 和 Rarity。
	输出：逐抽播放黑色剪影切换与奖励卡弹出；点击可跳过当前剪影，奖励页点击后继续或关闭。
	内部算法：轮播 VehicleCatalog 中的全部载具图标并用 Back 缓动缩放；最后切换为本次奖励卡。
	不负责：抽奖概率、货币扣除、载具发放、存档、箱子购买或奖励排序。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local VehicleCatalog = require(ReplicatedStorage.Shared.Vehicle.VehicleCatalog)
local CurrencyIconRenderer = require(script.Parent.CurrencyIconRenderer)

local VehicleLotteryPresentationController = {}

type ImageTarget = ImageLabel | ImageButton
type TextTarget = TextLabel | TextButton
type Phase = "Idle" | "Opening" | "Transition" | "Reward" | "Advancing"

type Reward = {
	VehicleId: string,
	Name: string,
	Rarity: string,
}

type References = {
	Root: GuiObject,
	MaskIcon: ImageTarget,
	Panel: GuiObject,
	PanelIcon: ImageTarget,
	NameValue: TextTarget,
	RarityValue: TextTarget,
	TitleValue: TextTarget,
	TipValue: TextTarget,
	MaskScale: UIScale,
	PanelScale: UIScale,
}

local MASK_SCALE_NAME = "LotteryOpeningScale"
local PANEL_SCALE_NAME = "LotteryRewardScale"
local MASK_START_SCALE = 0.68
local PANEL_START_SCALE = 0.72

local MASK_SWITCH_TWEEN_INFO = TweenInfo.new(
	0.5,
	Enum.EasingStyle.Back,
	Enum.EasingDirection.Out
)
local MASK_FINAL_TWEEN_INFO = TweenInfo.new(
	0.28,
	Enum.EasingStyle.Back,
	Enum.EasingDirection.Out
)
local PANEL_REVEAL_TWEEN_INFO = TweenInfo.new(
	0.32,
	Enum.EasingStyle.Back,
	Enum.EasingDirection.Out
)

local localPlayer = Players.LocalPlayer
local references: References? = nil
local phase: Phase = "Idle"
local presenting = false
local skipRequested = false
local activeTween: Tween? = nil
local advanceEvent = Instance.new("BindableEvent")
local started = false

local function resolveChild(parent: Instance?, name: string): Instance?
	return if parent then parent:FindFirstChild(name) else nil
end

local function resolveGuiObject(parent: Instance?, name: string): GuiObject?
	local child = resolveChild(parent, name)
	return if child and child:IsA("GuiObject") then child else nil
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

local function resolveScale(parent: GuiObject, name: string): (UIScale?, string?)
	local existing = parent:FindFirstChild(name)
	if existing and not existing:IsA("UIScale") then
		return nil, name .. "Invalid"
	end
	if existing then
		return existing :: UIScale, nil
	end

	local scale = Instance.new("UIScale")
	scale.Name = name
	scale.Scale = 1
	scale.Parent = parent
	return scale, nil
end

local function resolveReferences(playerGui: PlayerGui): (References?, string?)
	local mainGui = playerGui:FindFirstChild("Main")
	local root = resolveGuiObject(mainGui, "lottery")
	local maskIcon = resolveImageTarget(root, "Icon")
	local panel = resolveGuiObject(root, "Panel")
	local panelIcon = resolveImageTarget(panel, "Icon")
	local nameValue = resolveTextTarget(panel, "Name")
	local rarityValue = resolveTextTarget(panel, "Rarity")
	local titleValue = resolveTextTarget(root, "Title")
	local tipValue = resolveTextTarget(root, "Tip")

	if not mainGui then
		return nil, "MainGuiUnavailable"
	end
	if not root then
		return nil, "LotteryRootUnavailable"
	end
	if not maskIcon then
		return nil, "LotteryMaskIconUnavailable"
	end
	if not panel then
		return nil, "LotteryPanelUnavailable"
	end
	if not panelIcon then
		return nil, "LotteryPanelIconUnavailable"
	end
	if not nameValue then
		return nil, "LotteryNameUnavailable"
	end
	if not rarityValue then
		return nil, "LotteryRarityUnavailable"
	end
	if not titleValue then
		return nil, "LotteryTitleUnavailable"
	end
	if not tipValue then
		return nil, "LotteryTipUnavailable"
	end

	local maskScale, maskScaleReason = resolveScale(maskIcon, MASK_SCALE_NAME)
	if not maskScale then
		return nil, maskScaleReason
	end
	local panelScale, panelScaleReason = resolveScale(panel, PANEL_SCALE_NAME)
	if not panelScale then
		return nil, panelScaleReason
	end

	return {
		Root = root,
		MaskIcon = maskIcon,
		Panel = panel,
		PanelIcon = panelIcon,
		NameValue = nameValue,
		RarityValue = rarityValue,
		TitleValue = titleValue,
		TipValue = tipValue,
		MaskScale = maskScale,
		PanelScale = panelScale,
	}, nil
end

local function normalizeRewards(rawRewards): ({ Reward }?, string?)
	if type(rawRewards) ~= "table" or #rawRewards == 0 then
		return nil, "RewardsUnavailable"
	end

	local normalized = {}
	for index = 1, #rawRewards do
		local rawReward = rawRewards[index]
		if type(rawReward) ~= "table" then
			return nil, "RewardInvalid:" .. tostring(index)
		end

		local vehicleId = rawReward.VehicleId
		local definition = if type(vehicleId) == "string"
			then VehicleCatalog.Get(vehicleId)
			else nil
		if not definition then
			return nil, "RewardVehicleInvalid:" .. tostring(index)
		end

		local name = rawReward.Name
		if type(name) ~= "string" or name == "" then
			name = definition.Name
		end
		local rarity = rawReward.Rarity
		if type(rarity) ~= "string" or rarity == "" then
			rarity = definition.Rarity
		end

		table.insert(normalized, {
			VehicleId = definition.VehicleId,
			Name = name,
			Rarity = rarity,
		})
	end
	return normalized, nil
end

local function isAdvanceInput(input: InputObject): boolean
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		return true
	end
	return input.KeyCode == Enum.KeyCode.ButtonA
		or input.KeyCode == Enum.KeyCode.Return
		or input.KeyCode == Enum.KeyCode.Space
end

local function cancelActiveTween()
	local tween = activeTween
	if tween then
		activeTween = nil
		tween:Cancel()
	end
end

local function playTween(target: Instance, tweenInfo: TweenInfo, goal)
	cancelActiveTween()
	local tween = TweenService:Create(target, tweenInfo, goal)
	activeTween = tween
	tween:Play()
	tween.Completed:Wait()
	if activeTween == tween then
		activeTween = nil
	end
end

local function applyRarityGradients(parent: Instance, rarity: string)
	for _, child in parent:GetChildren() do
		if child:IsA("UIGradient") then
			child.Enabled = child.Name == rarity
		end
	end
end

local function applyMaskIcon(current: References, vehicleId: string)
	CurrencyIconRenderer.ApplyNamed(current.MaskIcon, vehicleId)
	current.MaskIcon.ImageColor3 = Color3.new(0, 0, 0)
end

local function playOpening(
	current: References,
	reward: Reward,
	drawIndex: number,
	totalDraws: number
)
	phase = "Opening"
	skipRequested = false
	current.Panel.Visible = false
	current.MaskIcon.Visible = true
	current.TitleValue.Text = if totalDraws > 1
		then string.format("Opening %d/%d...", drawIndex, totalDraws)
		else "Opening..."
	current.TipValue.Text = "Click to skip"

	local definitions = VehicleCatalog.GetAll()
	for offset = 1, #definitions do
		if skipRequested then
			break
		end
		local candidateIndex = ((drawIndex + offset - 2) % #definitions) + 1
		applyMaskIcon(current, definitions[candidateIndex].VehicleId)
		current.MaskScale.Scale = MASK_START_SCALE
		playTween(current.MaskScale, MASK_SWITCH_TWEEN_INFO, { Scale = 1 })
	end

	if not skipRequested then
		applyMaskIcon(current, reward.VehicleId)
		current.MaskScale.Scale = MASK_START_SCALE
		playTween(current.MaskScale, MASK_FINAL_TWEEN_INFO, { Scale = 1 })
	end
end

local function revealReward(
	current: References,
	reward: Reward,
	drawIndex: number,
	totalDraws: number
)
	phase = "Transition"
	cancelActiveTween()
	current.MaskIcon.Visible = false
	current.Panel.Visible = true
	CurrencyIconRenderer.ApplyNamed(current.PanelIcon, reward.VehicleId)
	current.NameValue.Text = reward.Name
	current.RarityValue.Text = reward.Rarity
	applyRarityGradients(current.Panel, reward.Rarity)
	applyRarityGradients(current.RarityValue, reward.Rarity)
	current.TitleValue.Text = if totalDraws > 1
		then string.format("Reward %d/%d", drawIndex, totalDraws)
		else "Reward"
	current.TipValue.Text = if drawIndex < totalDraws
		then "Click to continue"
		else "Click to close"

	current.PanelScale.Scale = PANEL_START_SCALE
	playTween(current.PanelScale, PANEL_REVEAL_TWEEN_INFO, { Scale = 1 })
	phase = "Reward"
	advanceEvent.Event:Wait()
end

local function closePresentation(current: References)
	cancelActiveTween()
	phase = "Idle"
	skipRequested = false
	current.Root.Visible = false
	current.Panel.Visible = false
	current.MaskIcon.Visible = true
	current.MaskScale.Scale = 1
	current.PanelScale.Scale = 1
	presenting = false
end

function VehicleLotteryPresentationController.Start(): boolean
	if started then
		return references ~= nil
	end
	started = true

	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	playerGui:WaitForChild("Main", 10)
	local resolved, reason = resolveReferences(playerGui)
	if not resolved then
		warn("载具抽奖 UI 路径无效：" .. tostring(reason))
		return false
	end

	references = resolved
	resolved.Root.Active = true
	resolved.Root.Visible = false
	resolved.Panel.Visible = false
	resolved.MaskIcon.Visible = true

	UserInputService.InputBegan:Connect(function(input)
		if not presenting or not isAdvanceInput(input) then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end

		if phase == "Opening" then
			skipRequested = true
			cancelActiveTween()
		elseif phase == "Reward" then
			phase = "Advancing"
			advanceEvent:Fire()
		end
	end)
	return true
end

function VehicleLotteryPresentationController.Play(rawRewards): (boolean, string?)
	if presenting then
		return false, "PresentationBusy"
	end
	if not VehicleLotteryPresentationController.Start() then
		return false, "PresentationUnavailable"
	end

	local rewards, reason = normalizeRewards(rawRewards)
	if not rewards then
		return false, reason
	end
	local current = references
	if not current then
		return false, "PresentationUnavailable"
	end

	presenting = true
	current.Root.Visible = true
	for drawIndex, reward in rewards do
		playOpening(current, reward, drawIndex, #rewards)
		revealReward(current, reward, drawIndex, #rewards)
	end
	closePresentation(current)
	return true, nil
end

return table.freeze(VehicleLotteryPresentationController)
