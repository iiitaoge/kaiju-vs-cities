--[[
	职责：连接 HUD 载具按钮、载具面板页签，并显示当前玩家的金币/钻石余额。
	输入：PlayerGui.HUD.Right.Vehicle、PlayerGui.Main.Vrhicle，以及玩家余额 Attributes。
	输出：点击 Vehicle 打开面板，点击 Close 关闭面板，DiamondVal/MoneyVal 显示最新余额，
	区域三未解锁时隐藏 HUD 载具入口，解锁后显示；
	Vrhicle/Crate/Map 三个页签显示唯一的 ON 状态；载具列表显示服务端车辆，
	并把派遣/召回、升级/销毁按钮请求交给服务器；Shop 显示箱子并接入钻石单抽、付费单抽/五连抽，
	DropRates 显示当前箱子的稀有度概率和载具列表。
	内部算法：启动时解析固定 UI 路径并隐藏面板；使用一个 activeTab 状态切换每个页签的
	ON/OFF Frame；使用一个 cratePage 和 activeCrateId 状态切换 Shop/DropRates 与箱子；
	监听按钮 Activated 和余额 Attribute 变化，通过显隐门控应用面板状态。
	不负责：派遣、战斗、奖励、模型生成或等级/货币计算。
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CompactNumberFormatter = require(
	ReplicatedStorage.Shared.UI.CompactNumberFormatter
)
local CurrencyIconRenderer = require(script.Parent.CurrencyIconRenderer)
local LocalCurrencyInfoRowLayout = require(script.Parent.LocalCurrencyInfoRowLayout)
local DiamondProtocol = require(ReplicatedStorage.Shared.Economy.DiamondProtocol)
local MoneyProtocol = require(ReplicatedStorage.Shared.Economy.MoneyProtocol)
local VehicleCatalog = require(ReplicatedStorage.Shared.Vehicle.VehicleCatalog)
local VehicleCrateConfigs = require(ReplicatedStorage.Shared.Vehicle.VehicleCrateConfigs)
local VehicleCrateProtocol = require(ReplicatedStorage.Shared.Vehicle.VehicleCrateProtocol)
local VehicleProgressionConfigs = require(
	ReplicatedStorage.Shared.Vehicle.VehicleProgressionConfigs
)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local LocalUIVisibilityGate = require(script.Parent.LocalUIVisibilityGate)
local LocalGuiButtonState = require(script.Parent.LocalGuiButtonState)
local VehicleDeploymentState = require(script.Parent.Parent.VehicleDeploymentState)
local VehicleCrateRemoteClient = require(
	script.Parent.Parent.Vehicle.VehicleCrateRemoteClient
)
local VehicleManagementRemoteClient = require(
	script.Parent.Parent.Vehicle.VehicleManagementRemoteClient
)
local PaidPurchaseRemoteClient = require(
	script.Parent.Parent.Monetization.PaidPurchaseRemoteClient
)
local PaidPurchaseProtocol = require(
	ReplicatedStorage.Shared.Monetization.PaidPurchaseProtocol
)
local NestMapRemoteClient = require(script.Parent.Parent.Nest.NestMapRemoteClient)
local NestMapUIController = require(script.Parent.Parent.Nest.NestMapUIController)
local SoundController = require(script.Parent.Parent.Sound.SoundController)
local TipBlackController = require(script.Parent.TipBlackController)
local VehicleLotteryPresentationController = require(
	script.Parent.VehicleLotteryPresentationController
)

local VehicleUIController = {}

-- Studio 原始 Robux 图标是写在 Val.Text 里的私有字符，不是独立 ImageLabel。
local ROBUX_ICON = utf8.char(0xE002)

type ImageTarget = ImageLabel | ImageButton
type TextTarget = TextLabel | TextButton
type TabId = "Vrhicle" | "Crate" | "Map"
type CratePage = "Shop" | "DropRates"
type CrateId = "Wood" | "Iron" | "Gold" | "Mythic"
type RarityId = "Common" | "UnCommon" | "Rare" | "Epic" | "Legendary" | "Mythical"

type TabReferences = {
	OnFrame: GuiObject,
	OffFrame: GuiObject,
	OnButton: GuiButton,
	OffButton: GuiButton,
}

type VehicleCardReferences = {
	Root: GuiObject,
	Icon: ImageLabel,
	DeployButton: GuiButton,
	DeployValue: TextTarget,
	DestroyButton: GuiButton,
	DestroyInfo: GuiObject,
	DestroyValue: TextTarget,
	UpgradeButton: GuiButton,
	UpgradeInfo: GuiObject,
	UpgradeValue: TextTarget,
	NameValue: TextTarget,
	LevelValue: TextTarget,
}

type CrateCardReferences = {
	Root: GuiObject,
	Icon: ImageTarget,
	TitleValue: TextTarget,
	DiamondButton: GuiButton,
	DiamondInfo: GuiObject,
	DiamondValue: TextTarget,
	RobuxButton: GuiButton,
	RobuxValue: TextTarget,
	FiveButton: GuiButton,
	FiveValue: TextTarget,
}

type CrateTabReferences = {
	OnFrame: GuiObject,
	OffFrame: GuiObject,
	OnButton: GuiButton,
	OffButton: GuiButton,
}

type DropRateUnitReferences = {
	Root: GuiObject,
	Icon: ImageLabel,
	TitleValue: TextTarget,
	RateValue: TextTarget,
}

type DropRateRarityReferences = {
	TitleValue: TextTarget,
	RateValue: TextTarget,
	List: GuiObject,
	UnitTemplate: GuiObject,
}

type References = {
	OpenButton: GuiButton,
	Root: GuiObject,
	CloseButton: GuiButton,
	DiamondValue: TextTarget,
	MoneyValue: TextTarget,
	Tabs: { [TabId]: TabReferences },
	VrhiclePanel: GuiObject,
	CratePanel: GuiObject,
	CrateShop: GuiObject,
	CrateDropRates: GuiObject,
	CrateDropRatesButton: GuiButton,
	CrateShopList: GuiObject,
	CrateShopUnitTemplate: GuiObject,
	CrateDropRatesBackButton: GuiButton,
	CrateTabs: { [CrateId]: CrateTabReferences },
	DropRateRarities: { [RarityId]: DropRateRarityReferences },
	VehicleScrollingFrame: ScrollingFrame,
	UnitList: GuiObject,
	UnitTemplate: GuiObject,
}

local CRATE_IDS: { CrateId } = { "Wood", "Iron", "Gold", "Mythic" }
local RARITY_IDS: { RarityId } = {
	"Common",
	"UnCommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythical",
}

local localPlayer = Players.LocalPlayer
local references: References? = nil
local visibilityGate: LocalUIVisibilityGate.Handle? = nil
local activeTab: TabId = "Vrhicle"
local cratePage: CratePage = "Shop"
local activeCrateId: CrateId = "Wood"
local vehicleActionBusy: { [string]: boolean } = {}
local crateActionBusy: { [string]: boolean } = {}
local refreshInFlight = false
local refreshQueued = false
local crateRefreshInFlight = false
local crateRefreshQueued = false
local crateState: any = nil
local vehicleCardWidth = 0
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

local function resolveTab(parent: Instance?, tabId: TabId): (TabReferences?, string?)
	local tab = resolveGuiObject(parent, tabId)
	local onFrame = resolveGuiObject(tab, "ON")
	local offFrame = resolveGuiObject(tab, "OFF")
	local onButton = resolveButton(onFrame, "Button")
	local offButton = resolveButton(offFrame, "Button")
	if not tab then
		return nil, tabId .. "TabUnavailable"
	end
	if not onFrame then
		return nil, tabId .. "OnFrameUnavailable"
	end
	if not offFrame then
		return nil, tabId .. "OffFrameUnavailable"
	end
	if not onButton then
		return nil, tabId .. "OnButtonUnavailable"
	end
	if not offButton then
		return nil, tabId .. "OffButtonUnavailable"
	end
	return {
		OnFrame = onFrame,
		OffFrame = offFrame,
		OnButton = onButton,
		OffButton = offButton,
	}, nil
end

local function resolveVehicleCard(unit: Instance): (VehicleCardReferences?, string?)
	local panel = resolveGuiObject(unit, "Panel")
	local info = resolveGuiObject(panel, "Info")
	local icon = resolveChild(info, "Icon")
	local nameValue = resolveTextTarget(info, "Name")
	local levelValue = resolveTextTarget(info, "Level")
	local button = resolveGuiObject(panel, "Button")
	local deploy = resolveGuiObject(button, "Deploy")
	local deployButton = resolveButton(deploy, "Button")
	local deployValue = resolveTextTarget(deployButton, "Val")
	local diamond = resolveGuiObject(button, "Diamond")
	local destroyButton = resolveButton(diamond, "Button")
	local destroyInfo = resolveGuiObject(destroyButton, "Info")
	local destroyValue = resolveTextTarget(destroyInfo, "Val")
	local money = resolveGuiObject(button, "Money")
	local upgradeButton = resolveButton(money, "Button")
	local upgradeInfo = resolveGuiObject(upgradeButton, "Info")
	local upgradeValue = resolveTextTarget(upgradeInfo, "Val")

	if not panel then
		return nil, "VehicleUnitPanelUnavailable"
	end
	if not info then
		return nil, "VehicleUnitInfoUnavailable"
	end
	if not icon or not icon:IsA("ImageLabel") then
		return nil, "VehicleUnitIconUnavailable"
	end
	if not nameValue then
		return nil, "VehicleUnitNameUnavailable"
	end
	if not levelValue then
		return nil, "VehicleUnitLevelUnavailable"
	end
	if not button then
		return nil, "VehicleUnitButtonUnavailable"
	end
	if not deploy then
		return nil, "VehicleUnitDeployUnavailable"
	end
	if not deployButton then
		return nil, "VehicleUnitDeployButtonUnavailable"
	end
	if not deployValue then
		return nil, "VehicleUnitDeployValueUnavailable"
	end
	if not diamond then
		return nil, "VehicleUnitDiamondUnavailable"
	end
	if not destroyButton then
		return nil, "VehicleUnitDestroyButtonUnavailable"
	end
	if not destroyInfo then
		return nil, "VehicleUnitDestroyInfoUnavailable"
	end
	if not destroyValue then
		return nil, "VehicleUnitDestroyValueUnavailable"
	end
	if not money then
		return nil, "VehicleUnitMoneyUnavailable"
	end
	if not upgradeButton then
		return nil, "VehicleUnitUpgradeButtonUnavailable"
	end
	if not upgradeInfo then
		return nil, "VehicleUnitUpgradeInfoUnavailable"
	end
	if not upgradeValue then
		return nil, "VehicleUnitUpgradeValueUnavailable"
	end

	return {
		Root = unit :: GuiObject,
		Icon = icon,
		DeployButton = deployButton,
		DeployValue = deployValue,
		DestroyButton = destroyButton,
		DestroyInfo = destroyInfo,
		DestroyValue = destroyValue,
		UpgradeButton = upgradeButton,
		UpgradeInfo = upgradeInfo,
		UpgradeValue = upgradeValue,
		NameValue = nameValue,
		LevelValue = levelValue,
	}, nil
end

local function resolveCrateCard(unit: Instance): (CrateCardReferences?, string?)
	local panel = resolveGuiObject(unit, "Panel")
	local icon = resolveImageTarget(panel, "Icon")
	local titleValue = resolveTextTarget(panel, "Title")
	local button = resolveGuiObject(panel, "Button")
	local diamond = resolveGuiObject(button, "Diamond")
	local diamondButton = resolveButton(diamond, "Button")
	local diamondInfo = resolveGuiObject(diamondButton, "Info")
	local diamondValue = resolveTextTarget(diamondInfo, "Val")
	local robux = resolveGuiObject(button, "Robux")
	local robuxButton = resolveButton(robux, "Button")
	local robuxValue = resolveTextTarget(robuxButton, "Val")
	local five = resolveGuiObject(button, "5x")
	local fiveButton = resolveButton(five, "Button")
	local fiveValue = resolveTextTarget(fiveButton, "Val")

	if not panel then
		return nil, "CrateUnitPanelUnavailable"
	end
	if not icon then
		return nil, "CrateUnitIconUnavailable"
	end
	if not titleValue then
		return nil, "CrateUnitTitleUnavailable"
	end
	if not button then
		return nil, "CrateUnitButtonUnavailable"
	end
	if not diamondButton then
		return nil, "CrateUnitDiamondButtonUnavailable"
	end
	if not diamondValue then
		return nil, "CrateUnitDiamondValueUnavailable"
	end
	if not robuxButton then
		return nil, "CrateUnitRobuxButtonUnavailable"
	end
	if not robuxValue then
		return nil, "CrateUnitRobuxValueUnavailable"
	end
	if not fiveButton then
		return nil, "CrateUnitFiveButtonUnavailable"
	end
	if not fiveValue then
		return nil, "CrateUnitFiveValueUnavailable"
	end

	return {
		Root = unit :: GuiObject,
		Icon = icon,
		TitleValue = titleValue,
		DiamondButton = diamondButton,
		DiamondInfo = diamondInfo,
		DiamondValue = diamondValue,
		RobuxButton = robuxButton,
		RobuxValue = robuxValue,
		FiveButton = fiveButton,
		FiveValue = fiveValue,
	}, nil
end

local function resolveCrateTab(parent: Instance?, crateId: CrateId): (CrateTabReferences?, string?)
	local tab = resolveGuiObject(parent, crateId)
	local onFrame = resolveGuiObject(tab, "ON")
	local offFrame = resolveGuiObject(tab, "OFF")
	local onButton = resolveButton(onFrame, "Button")
	local offButton = resolveButton(offFrame, "Button")
	if not tab then
		return nil, crateId .. "CrateTabUnavailable"
	end
	if not onFrame or not offFrame then
		return nil, crateId .. "CrateTabStateUnavailable"
	end
	if not onButton or not offButton then
		return nil, crateId .. "CrateTabButtonUnavailable"
	end
	return {
		OnFrame = onFrame,
		OffFrame = offFrame,
		OnButton = onButton,
		OffButton = offButton,
	}, nil
end

local function resolveDropRateRarity(
	left: Instance?,
	rarity: RarityId
): (DropRateRarityReferences?, string?)
	local title = resolveGuiObject(left, rarity .. "Title")
	local list = resolveGuiObject(left, rarity .. "Left")
	local titleValue = resolveTextTarget(title, "Title")
	local rateValue = resolveTextTarget(title, "Val")
	local unitTemplate = resolveGuiObject(list, "Unit")
	if not title then
		return nil, rarity .. "TitleUnavailable"
	end
	if not list then
		return nil, rarity .. "ListUnavailable"
	end
	if not titleValue or not rateValue then
		return nil, rarity .. "RateHeaderUnavailable"
	end
	if not unitTemplate then
		return nil, rarity .. "UnitTemplateUnavailable"
	end
	return {
		TitleValue = titleValue,
		RateValue = rateValue,
		List = list,
		UnitTemplate = unitTemplate,
	}, nil
end

local function resolveDropRateUnit(unit: Instance): (DropRateUnitReferences?, string?)
	local panel = resolveGuiObject(unit, "Panel")
	local icon = resolveChild(panel, "Icon")
	local titleValue = resolveTextTarget(panel, "Title")
	local rateValue = resolveTextTarget(panel, "Val")
	if not panel then
		return nil, "DropRateUnitPanelUnavailable"
	end
	if not icon or not icon:IsA("ImageLabel") then
		return nil, "DropRateUnitIconUnavailable"
	end
	if not titleValue then
		return nil, "DropRateUnitTitleUnavailable"
	end
	if not rateValue then
		return nil, "DropRateUnitValueUnavailable"
	end
	return {
		Root = unit :: GuiObject,
		Icon = icon,
		TitleValue = titleValue,
		RateValue = rateValue,
	}, nil
end

local function resolveReferences(playerGui: PlayerGui): (References?, string?)
	local hud = playerGui:FindFirstChild("HUD")
	local right = resolveGuiObject(hud, "Right")
	local openButton = resolveButton(right, "Vehicle")

	local mainGui = playerGui:FindFirstChild("Main")
	local root = resolveGuiObject(mainGui, "Vrhicle")
	local mainAll = resolveGuiObject(root, "MainAll")
	local title = resolveGuiObject(mainAll, "Title")
	local closeButton = resolveButton(title, "Close")
	local main = resolveGuiObject(mainAll, "Main")
	local top = resolveGuiObject(main, "Top")
	local data = resolveGuiObject(top, "Data")
	local button = resolveGuiObject(top, "Button")
	local vrhiclePanel = resolveGuiObject(main, "VrhiclePanel")
	local cratePanel = resolveGuiObject(main, "CratePanel")
	local crateShop = resolveGuiObject(cratePanel, "Shop")
	local shopDropRates = resolveGuiObject(crateShop, "DropRates")
	local crateDropRates = resolveGuiObject(cratePanel, "DropRates")
	local crateDropRatesButton = resolveButton(shopDropRates, "Button")
	local crateShopList = resolveGuiObject(crateShop, "ScrollingFrame")
	local crateShopUnitTemplate = resolveGuiObject(crateShopList, "Unit")
	local crateDropRatesTitle = resolveGuiObject(crateDropRates, "Title")
	local crateDropRatesBack = resolveGuiObject(crateDropRatesTitle, "Back")
	local crateDropRatesBackButton = resolveButton(crateDropRatesBack, "Button")
	local crateDropRatesButtonList = resolveGuiObject(crateDropRates, "Button")
	local crateDropRatesLeft = resolveGuiObject(crateDropRates, "Left")
	local scrollingFrame = resolveGuiObject(vrhiclePanel, "ScrollingFrame")
	local unitList = resolveGuiObject(scrollingFrame, "List")
	local unitTemplate = resolveGuiObject(unitList, "Unit")
	local diamondValue = resolveTextTarget(data, "DiamondVal")
	local moneyValue = resolveTextTarget(data, "MoneyVal")

	if not hud then
		return nil, "HUDUnavailable"
	end
	if not right then
		return nil, "HUDRightUnavailable"
	end
	if not openButton then
		return nil, "VehicleButtonUnavailable"
	end
	if not mainGui then
		return nil, "MainGuiUnavailable"
	end
	if not root then
		return nil, "VehiclePanelUnavailable"
	end
	if not mainAll then
		return nil, "VehicleMainAllUnavailable"
	end
	if not title then
		return nil, "VehicleTitleUnavailable"
	end
	if not closeButton then
		return nil, "VehicleCloseUnavailable"
	end
	if not main then
		return nil, "VehicleMainUnavailable"
	end
	if not top then
		return nil, "VehicleTopUnavailable"
	end
	if not data then
		return nil, "VehicleDataUnavailable"
	end
	if not button then
		return nil, "VehicleTabButtonUnavailable"
	end
	if not vrhiclePanel then
		return nil, "VrhiclePanelUnavailable"
	end
	if not cratePanel then
		return nil, "CratePanelUnavailable"
	end
	if not crateShop then
		return nil, "CrateShopUnavailable"
	end
	if not shopDropRates then
		return nil, "ShopDropRatesUnavailable"
	end
	if not crateDropRates then
		return nil, "CrateDropRatesUnavailable"
	end
	if not crateDropRatesButton then
		return nil, "CrateDropRatesButtonUnavailable"
	end
	if not crateShopList then
		return nil, "CrateShopListUnavailable"
	end
	if not crateShopUnitTemplate then
		return nil, "CrateShopUnitTemplateUnavailable"
	end
	if not crateDropRatesTitle then
		return nil, "CrateDropRatesTitleUnavailable"
	end
	if not crateDropRatesBackButton then
		return nil, "CrateDropRatesBackButtonUnavailable"
	end
	if not crateDropRatesButtonList then
		return nil, "CrateDropRatesButtonListUnavailable"
	end
	if not crateDropRatesLeft then
		return nil, "CrateDropRatesLeftUnavailable"
	end
	if not scrollingFrame then
		return nil, "VehicleScrollingFrameUnavailable"
	end
	if not scrollingFrame:IsA("ScrollingFrame") then
		return nil, "VehicleScrollingFrameInvalid"
	end
	if not unitList then
		return nil, "VehicleUnitListUnavailable"
	end
	if not unitTemplate then
		return nil, "VehicleUnitTemplateUnavailable"
	end
	if not diamondValue then
		return nil, "VehicleDiamondValueUnavailable"
	end
	if not moneyValue then
		return nil, "VehicleMoneyValueUnavailable"
	end

	local tabs: { [TabId]: TabReferences } = {}
	for _, tabId in { "Vrhicle", "Crate", "Map" } do
		local tab, tabReason = resolveTab(button, tabId :: TabId)
		if not tab then
			return nil, tabReason
		end
		tabs[tabId :: TabId] = tab
	end

	local crateTabs: { [CrateId]: CrateTabReferences } = {}
	for _, crateId in CRATE_IDS do
		local tab, tabReason = resolveCrateTab(crateDropRatesButtonList, crateId)
		if not tab then
			return nil, tabReason
		end
		crateTabs[crateId] = tab
	end

	local dropRateRarities: { [RarityId]: DropRateRarityReferences } = {}
	for _, rarity in RARITY_IDS do
		local resolvedRarity, rarityReason = resolveDropRateRarity(crateDropRatesLeft, rarity)
		if not resolvedRarity then
			return nil, rarityReason
		end
		dropRateRarities[rarity] = resolvedRarity
	end

	return {
		OpenButton = openButton,
		Root = root,
		CloseButton = closeButton,
		DiamondValue = diamondValue,
		MoneyValue = moneyValue,
		Tabs = tabs,
		VrhiclePanel = vrhiclePanel,
		CratePanel = cratePanel,
		CrateShop = crateShop,
		CrateDropRates = crateDropRates,
		CrateDropRatesButton = crateDropRatesButton,
		CrateShopList = crateShopList,
		CrateShopUnitTemplate = crateShopUnitTemplate,
		CrateDropRatesBackButton = crateDropRatesBackButton,
		CrateTabs = crateTabs,
		DropRateRarities = dropRateRarities,
		VehicleScrollingFrame = scrollingFrame,
		UnitList = unitList,
		UnitTemplate = unitTemplate,
	}, nil
end

local function formatBalance(value: any): string
	return CompactNumberFormatter.Format(
		if type(value) == "number" and value == value and value < math.huge and value >= 0
			then value
			else 0
	)
end

local CRATE_FAILURE_MESSAGES: { [string]: string } = {
	R3Locked = "Unlock Region 3 to use vehicles.",
	InsufficientDiamonds = "Not enough diamonds.",
	PlayerDataNotReady = "Player data is still loading. Please try again.",
	ActionBusy = "Please wait for the current draw to finish.",
	UnknownCrate = "This crate is unavailable.",
}

local VEHICLE_MANAGEMENT_FAILURE_MESSAGES: { [string]: string } = {
	VehicleDeployed = "Deployed vehicles cannot be upgraded or destroyed.",
	VehicleAlreadyDeployed = "Deployed vehicles cannot be upgraded or destroyed.",
	InsufficientFunds = "Not enough money.",
	PlayerDataNotReady = "Player data is still loading. Please try again.",
	VehicleNotOwned = "This vehicle is no longer available.",
	CannotDestroyLastVehicle = "You cannot destroy your last vehicle.",
	MaxLevel = "This vehicle is already at max level.",
	ActionBusy = "Please wait for the current action to finish.",
}

local VEHICLE_RECALL_FAILURE_MESSAGES: { [string]: string } = {
	VehicleInBattle = "Vehicles in battle cannot be recalled.",
	VehicleNotDispatched = "This vehicle is no longer deployed.",
	PlayerDataNotReady = "Player data is still loading. Please try again.",
	ActionBusy = "Please wait for the current action to finish.",
}

local function showCratePurchaseResult(response)
	if response.Succeeded then
		local rewards = response.Rewards
		if type(rewards) == "table" and #rewards > 0 then
			local played, reason = VehicleLotteryPresentationController.Play(rewards)
			if played then
				return
			end
			warn("载具抽奖演出未播放：" .. tostring(reason))
		end

		local reward = if type(rewards) == "table" then rewards[1] else nil
		if type(reward) == "table" and type(reward.Name) == "string" then
			TipBlackController.ShowMessage("Obtained: " .. reward.Name)
		else
			TipBlackController.ShowMessage("Crate opened!")
		end
		return
	end

	local reason = tostring(response.Reason)
	TipBlackController.ShowMessage(
		CRATE_FAILURE_MESSAGES[reason] or "Crate purchase failed. Please try again."
	)
end

local function showVehicleManagementResult(response, action: "Upgrade" | "Destroy")
	if response.Succeeded then
		if action == "Destroy" and type(response.DiamondReward) == "number" then
			TipBlackController.ShowMessage(
				"Vehicle destroyed. +"
					.. formatBalance(response.DiamondReward)
					.. " diamonds."
			)
		else
			TipBlackController.ShowMessage("Vehicle upgraded!")
		end
		return
	end

	local reason = tostring(response.Reason)
	TipBlackController.ShowMessage(
		VEHICLE_MANAGEMENT_FAILURE_MESSAGES[reason]
			or "Vehicle action failed. Please try again."
	)
end

local function showVehicleRecallResult(response)
	if response.Succeeded then
		TipBlackController.ShowMessage("Vehicle recalled.")
		return
	end

	local reason = tostring(response.Reason)
	TipBlackController.ShowMessage(
		VEHICLE_RECALL_FAILURE_MESSAGES[reason]
			or "Vehicle recall failed. Please try again."
	)
end

local function refreshBalances()
	local current = references
	if not current then
		return
	end
	current.DiamondValue.Text = formatBalance(
		localPlayer:GetAttribute(DiamondProtocol.BalanceAttributeName)
	)
	current.MoneyValue.Text = formatBalance(
		localPlayer:GetAttribute(MoneyProtocol.BalanceAttributeName)
	)
end

local function setVisible(nextVisible: boolean)
	if visibilityGate then
		visibilityGate:SetDesiredVisible(nextVisible)
	elseif references then
		references.Root.Visible = nextVisible
	end
end

local function applyFeatureVisibility(unlocked: boolean)
	local current = references
	if not current then
		return
	end

	current.OpenButton.Visible = unlocked
	if not unlocked and current.Root.Visible then
		setVisible(false)
	end
end

local function setButtonEnabled(button: GuiButton, enabled: boolean)
	LocalGuiButtonState.SetEnabled(button, enabled)
end

local function setVehicleCardWidth(unit: GuiObject)
	if vehicleCardWidth <= 0 then
		return
	end
	local size = unit.Size
	local nextSize = UDim2.new(0, vehicleCardWidth, size.Y.Scale, size.Y.Offset)
	if size ~= nextSize then
		unit.Size = nextSize
	end
end

local function configureVehicleList()
	local current = references
	if not current then
		return
	end

	local scrollingFrame = current.VehicleScrollingFrame
	scrollingFrame.Active = true
	scrollingFrame.ScrollingEnabled = true
	scrollingFrame.ScrollingDirection = Enum.ScrollingDirection.X
	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	scrollingFrame.ElasticBehavior = Enum.ElasticBehavior.Never
	scrollingFrame.CanvasPosition = Vector2.zero

	-- List 内部已经有横向 UIListLayout；左对齐后从第一台车开始显示，
	-- 用 UIListLayout 的实际内容宽度更新 ScrollingFrame 的横向 Canvas。
	local layout = current.UnitList:FindFirstChildOfClass("UIListLayout")
	if layout and layout:IsA("UIListLayout") then
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Wraps = false

		local function clampCanvasPosition()
			local viewportSize = scrollingFrame.AbsoluteSize
			local canvasWidth = scrollingFrame.CanvasSize.X.Offset
			local maximumX = math.max(0, canvasWidth - viewportSize.X)
			local current = scrollingFrame.CanvasPosition
			local nextPosition = Vector2.new(math.clamp(current.X, 0, maximumX), 0)
			if current ~= nextPosition then
				scrollingFrame.CanvasPosition = nextPosition
			end
		end

		local function updateCanvasSize()
			local viewportSize = scrollingFrame.AbsoluteSize
			local contentSize = layout.AbsoluteContentSize
			scrollingFrame.CanvasSize = UDim2.fromOffset(
				math.max(contentSize.X, viewportSize.X),
				viewportSize.Y
			)
			clampCanvasPosition()
		end

		local function updateCardWidth()
			vehicleCardWidth = math.max(
				1,
				math.floor(scrollingFrame.AbsoluteSize.X * 0.25 + 0.5)
			)
			for _, child in current.UnitList:GetChildren() do
				if child:IsA("GuiObject") then
					setVehicleCardWidth(child)
				end
			end
			updateCanvasSize()
		end

		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
		scrollingFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(clampCanvasPosition)
		scrollingFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCardWidth)
		updateCardWidth()
	else
		warn("载具列表缺少 UIListLayout")
	end
end

local function formatRate(value: any): string
	if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return "0%"
	end
	if value % 1 == 0 then
		return tostring(value) .. "%"
	end
	return string.format("%.2f%%", value)
end

local refreshVehicles
local refreshCrates
local renderDropRates

local function applyContentState()
	local current = references
	if not current then
		return
	end

	local showingVrhicle = activeTab == "Vrhicle"
	local showingCrate = activeTab == "Crate"
	current.VrhiclePanel.Visible = showingVrhicle
	current.CratePanel.Visible = showingCrate
	current.CrateShop.Visible = showingCrate and cratePage == "Shop"
	current.CrateDropRates.Visible = showingCrate and cratePage == "DropRates"
end

local function applyTabState(nextTab: TabId)
	local current = references
	if not current then
		return
	end

	if nextTab == "Crate" and activeTab ~= "Crate" then
		cratePage = "Shop"
		task.spawn(function()
			if refreshCrates then
				refreshCrates()
			end
		end)
	end
	activeTab = nextTab
	for tabId, tab in current.Tabs do
		local selected = tabId == activeTab
		tab.OnFrame.Visible = selected
		tab.OffFrame.Visible = not selected
		setButtonEnabled(tab.OnButton, selected)
		setButtonEnabled(tab.OffButton, not selected)
	end
	applyContentState()
	local showVehiclePanel = activeTab ~= "Map"
	if visibilityGate then
		visibilityGate:SetDesiredVisible(showVehiclePanel)
	else
		current.Root.Visible = showVehiclePanel
	end
	if activeTab == "Map" then
		NestMapUIController.Open()
	else
		NestMapUIController.Close()
	end
end

local function showDropRates()
	cratePage = "DropRates"
	applyContentState()
	if renderDropRates and crateState then
		renderDropRates(activeCrateId)
	elseif refreshCrates then
		task.spawn(refreshCrates)
	end
end

local function showCrateShop()
	cratePage = "Shop"
	applyContentState()
end

local function clearCrateCards()
	local current = references
	if not current then
		return
	end
	current.CrateShopUnitTemplate.Visible = false
	for _, child in current.CrateShopList:GetChildren() do
		if child:GetAttribute("LocalVehicleCrateUnit") == true then
			child:Destroy()
		end
	end
end

local function getCrate(state, crateId: CrateId)
	if type(state) ~= "table" or type(state.Crates) ~= "table" then
		return nil
	end
	for _, crate in state.Crates do
		if crate.CrateId == crateId then
			return crate
		end
	end
	return nil
end

local function renderCrateCard(crate, layoutOrder: number)
	local current = references
	if not current then
		return
	end

	local unit = current.CrateShopUnitTemplate:Clone()
	local crateId = tostring(crate.CrateId or "")
	unit.Name = "VehicleCrateUnit_" .. crateId
	unit:SetAttribute("LocalVehicleCrateUnit", true)
	unit.LayoutOrder = layoutOrder
	unit.Visible = true

	local card, reason = resolveCrateCard(unit)
	if not card then
		unit:Destroy()
		warn("载具箱子 Unit 模板无效：" .. tostring(reason))
		return
	end

	local crateConfig = VehicleCrateConfigs.Get(crateId)
	local iconName = if crateConfig then crateConfig.IconName else ""
	CurrencyIconRenderer.ApplyNamed(card.Icon, iconName)
	LocalCurrencyInfoRowLayout.Configure(card.DiamondInfo, false)
	card.TitleValue.Text = tostring(crate.Name or crateId)
	card.DiamondValue.Text = formatBalance(crate.DiamondPrice)
	local robuxSingleProductId = if type(crate.RobuxSingleProductId) == "number"
		then crate.RobuxSingleProductId
		else 0
	local robuxFiveProductId = if type(crate.RobuxFiveDrawProductId) == "number"
		then crate.RobuxFiveDrawProductId
		else 0
	local robuxSinglePrice = if crateConfig
		and type(crateConfig.RobuxSinglePriceInRobux) == "number"
		then crateConfig.RobuxSinglePriceInRobux
		else nil
	local robuxFivePrice = if crateConfig
		and type(crateConfig.RobuxFiveDrawPriceInRobux) == "number"
		then crateConfig.RobuxFiveDrawPriceInRobux
		else nil
	card.RobuxValue.Text = if robuxSingleProductId > 0 and robuxSinglePrice
		then ROBUX_ICON .. formatBalance(robuxSinglePrice)
		else "Soon"
	card.FiveValue.Text = if robuxFiveProductId > 0 and robuxFivePrice
		then "5x " .. ROBUX_ICON .. formatBalance(robuxFivePrice)
		else "Soon"

	local busy = crateActionBusy[crateId] == true
	local paidRandomItemsAllowed = localPlayer:GetAttribute(
		PaidPurchaseProtocol.PaidRandomItemsAllowedAttributeName
	) == true
	-- 区域三仍由服务端校验；客户端保持可点击，确保锁定/余额不足时能显示原因。
	setButtonEnabled(card.DiamondButton, not busy)
	setButtonEnabled(card.FiveButton, paidRandomItemsAllowed and robuxFiveProductId > 0 and not busy)
	setButtonEnabled(card.RobuxButton, paidRandomItemsAllowed and robuxSingleProductId > 0 and not busy)

	local function purchaseDiamond()
		if crateActionBusy[crateId] then
			return
		end
		crateActionBusy[crateId] = true
		setButtonEnabled(card.DiamondButton, false)
		setButtonEnabled(card.FiveButton, false)
		setButtonEnabled(card.RobuxButton, false)
		task.spawn(function()
			local response = VehicleCrateRemoteClient.PurchaseDiamond(
				crateId,
				VehicleCrateProtocol.DrawCounts.Single
			)
			if response.Succeeded then
				SoundController.Play("Yes")
			else
				if response.Reason ~= "RequestFailed"
					and response.Reason ~= "InvalidServerResponse"
					and response.Reason ~= "PlayerDataNotReady"
				then
					SoundController.Play("No")
				end
				warn(string.format(
					"载具箱子购买失败：%s/%d (%s)",
					crateId,
					VehicleCrateProtocol.DrawCounts.Single,
					tostring(response.Reason)
				))
			end
			showCratePurchaseResult(response)
			crateActionBusy[crateId] = nil
			refreshBalances()
			if refreshVehicles then
				task.spawn(refreshVehicles)
			end
			if refreshCrates then
				task.spawn(refreshCrates)
			end
		end)
	end

	local function purchaseRobux(productId: number)
		if crateActionBusy[crateId] or productId <= 0 then
			return
		end
		if localPlayer:GetAttribute(
			PaidPurchaseProtocol.PaidRandomItemsAllowedAttributeName
		) ~= true then
			TipBlackController.ShowMessage("Paid crate purchases are unavailable.")
			return
		end
		crateActionBusy[crateId] = true
		setButtonEnabled(card.DiamondButton, false)
		setButtonEnabled(card.FiveButton, false)
		setButtonEnabled(card.RobuxButton, false)
		local prompted = pcall(function()
			MarketplaceService:PromptProductPurchase(localPlayer, productId)
		end)
		if not prompted then
			crateActionBusy[crateId] = nil
			TipBlackController.ShowMessage("Unable to open purchase dialog.")
		end
	end

	card.DiamondButton.Activated:Connect(function()
		purchaseDiamond()
	end)
	card.FiveButton.Activated:Connect(function()
		purchaseRobux(robuxFiveProductId)
	end)
	card.RobuxButton.Activated:Connect(function()
		purchaseRobux(robuxSingleProductId)
	end)
	unit.Parent = current.CrateShopList
end

local function clearDropRateUnits(rarity: RarityId)
	local current = references
	local resolved = current and current.DropRateRarities[rarity]
	if not resolved then
		return
	end
	resolved.UnitTemplate.Visible = false
	for _, child in resolved.List:GetChildren() do
		if child:GetAttribute("LocalVehicleDropRateUnit") == true then
			child:Destroy()
		end
	end
end

local function renderDropRateUnit(
	resolved: DropRateRarityReferences,
	vehicle,
	rate: number,
	layoutOrder: number
)
	local unit = resolved.UnitTemplate:Clone()
	unit.Name = "VehicleDropRateUnit_" .. tostring(vehicle.VehicleId)
	unit:SetAttribute("LocalVehicleDropRateUnit", true)
	unit.LayoutOrder = layoutOrder
	unit.Visible = true

	local card, reason = resolveDropRateUnit(unit)
	if not card then
		unit:Destroy()
		warn("载具 DropRates Unit 模板无效：" .. tostring(reason))
		return
	end

	CurrencyIconRenderer.ApplyNamed(card.Icon, tostring(vehicle.IconName or vehicle.VehicleId or ""))
	card.TitleValue.Text = tostring(vehicle.Name or vehicle.VehicleId or "Vehicle")
	card.RateValue.Text = formatRate(rate)
	unit.Parent = resolved.List
end

local function applyCrateSelection(crateId: CrateId)
	local current = references
	if not current then
		return
	end
	activeCrateId = crateId
	for id, tab in current.CrateTabs do
		local selected = id == activeCrateId
		tab.OnFrame.Visible = selected
		tab.OffFrame.Visible = not selected
		setButtonEnabled(tab.OnButton, selected)
		setButtonEnabled(tab.OffButton, not selected)
	end
	if renderDropRates then
		renderDropRates(activeCrateId)
	end
end

renderDropRates = function(crateId: CrateId)
	local current = references
	local state = crateState
	if not current or type(state) ~= "table" then
		return
	end
	local crate = getCrate(state, crateId)
	if not crate then
		return
	end

	local vehiclesByRarity: { [RarityId]: { any } } = {}
	for _, rarity in RARITY_IDS do
		vehiclesByRarity[rarity] = {}
		clearDropRateUnits(rarity)
	end
	if type(state.Vehicles) == "table" then
		for _, vehicle in state.Vehicles do
			local rarity = vehicle.Rarity
			if vehiclesByRarity[rarity] then
				table.insert(vehiclesByRarity[rarity], vehicle)
			end
		end
	end

	for _, rarity in RARITY_IDS do
		local resolved = current.DropRateRarities[rarity]
		local rate = if type(crate.RarityRates) == "table"
			and type(crate.RarityRates[rarity]) == "number"
			then crate.RarityRates[rarity]
			else 0
		resolved.TitleValue.Text = rarity
		resolved.RateValue.Text = formatRate(rate)

		local vehicles = vehiclesByRarity[rarity]
		local vehicleRate = if #vehicles > 0 then rate / #vehicles else 0
		for index, vehicle in vehicles do
			renderDropRateUnit(resolved, vehicle, vehicleRate, index)
		end
	end
end

local function selectCrate(crateId: CrateId)
	applyCrateSelection(crateId)
end

local function clearVehicleCards()
	local current = references
	if not current then
		return
	end
	current.UnitTemplate.Visible = false
	for _, child in current.UnitList:GetChildren() do
		if child:GetAttribute("LocalVehicleUnit") == true then
			child:Destroy()
		end
	end
end

local function renderVehicleCard(vehicle)
	local current = references
	if not current then
		return
	end

	local unit = current.UnitTemplate:Clone()
	local instanceId = tostring(vehicle.InstanceId or "")
	unit.Name = "VehicleUnit_" .. tostring(vehicle.InstanceId)
	unit:SetAttribute("LocalVehicleUnit", true)
	unit.LayoutOrder = tonumber(string.match(instanceId, "%d+$")) or 0
	unit.Visible = true
	setVehicleCardWidth(unit)

	local card, reason = resolveVehicleCard(unit)
	if not card then
		unit:Destroy()
		warn("载具 Unit 模板无效：" .. tostring(reason))
		return
	end
	local vehicleId = tostring(vehicle.VehicleId or "")
	local fallbackDefinition = VehicleCatalog.Get(vehicleId)
	local level = if type(vehicle.Level) == "number" then vehicle.Level else 1
	local active = vehicle.Active == true
	CurrencyIconRenderer.ApplyNamed(card.Icon, vehicleId)
	local displayName = vehicle.Name
	if type(displayName) ~= "string" or displayName == "" then
		displayName = if fallbackDefinition then fallbackDefinition.Name else vehicleId
	end
	card.NameValue.Text = tostring(displayName)
	card.LevelValue.Text = "Lv." .. tostring(level)
	card.DestroyValue.Text = "+" .. formatBalance(vehicle.DestroyReward)
	card.UpgradeValue.Text = if level >= VehicleProgressionConfigs.MaxLevel
		then "MAX"
		else formatBalance(vehicle.UpgradeCost)
	LocalCurrencyInfoRowLayout.Configure(card.DestroyInfo, true)
	LocalCurrencyInfoRowLayout.Configure(card.UpgradeInfo, false)
	card.DeployValue.Text = if active then "Recall" else "Deploy"
	setButtonEnabled(card.DestroyButton, not active and not vehicleActionBusy[instanceId])
	setButtonEnabled(
		card.UpgradeButton,
		not active
		and level < VehicleProgressionConfigs.MaxLevel
		and not vehicleActionBusy[instanceId]
	)
	setButtonEnabled(card.DeployButton, not vehicleActionBusy[instanceId])

	card.DeployButton.Activated:Connect(function()
		if vehicleActionBusy[instanceId] then
			return
		end
		if active then
			vehicleActionBusy[instanceId] = true
			setButtonEnabled(card.DeployButton, false)
			task.spawn(function()
				local response = NestMapRemoteClient.Recall(instanceId)
				vehicleActionBusy[instanceId] = nil
				if response.Succeeded then
					SoundController.Play("Yes")
				else
					if response.Reason ~= "RequestFailed"
						and response.Reason ~= "InvalidServerResponse"
						and response.Reason ~= "PlayerDataNotReady"
					then
						SoundController.Play("No")
					end
				end
				showVehicleRecallResult(response)
				refreshVehicles()
			end)
			return
		end
		VehicleDeploymentState.Begin(instanceId)
		card.DeployValue.Text = "Select Nest"
		applyTabState("Map")
	end)
	card.UpgradeButton.Activated:Connect(function()
		if active
			or level >= VehicleProgressionConfigs.MaxLevel
			or vehicleActionBusy[instanceId]
		then
			return
		end
		vehicleActionBusy[instanceId] = true
		setButtonEnabled(card.UpgradeButton, false)
		setButtonEnabled(card.DestroyButton, false)
		task.spawn(function()
			local response = VehicleManagementRemoteClient.Upgrade(instanceId)
			vehicleActionBusy[instanceId] = nil
			if response.Succeeded then
				SoundController.Play("Yes")
			else
				if response.Reason ~= "RequestFailed"
					and response.Reason ~= "InvalidServerResponse"
					and response.Reason ~= "PlayerDataNotReady"
				then
					SoundController.Play("No")
				end
				warn(string.format("载具升级失败：%s (%s)", instanceId, tostring(response.Reason)))
			end
			showVehicleManagementResult(response, "Upgrade")
			refreshBalances()
			refreshVehicles()
		end)
	end)
	card.DestroyButton.Activated:Connect(function()
		if active or vehicleActionBusy[instanceId] then
			return
		end
		vehicleActionBusy[instanceId] = true
		setButtonEnabled(card.UpgradeButton, false)
		setButtonEnabled(card.DestroyButton, false)
		task.spawn(function()
			local response = VehicleManagementRemoteClient.Destroy(instanceId)
			vehicleActionBusy[instanceId] = nil
			if response.Succeeded then
				SoundController.Play("Yes")
			else
				if response.Reason ~= "RequestFailed"
					and response.Reason ~= "InvalidServerResponse"
					and response.Reason ~= "PlayerDataNotReady"
				then
					SoundController.Play("No")
				end
				warn(string.format("载具销毁失败：%s (%s)", instanceId, tostring(response.Reason)))
			end
			showVehicleManagementResult(response, "Destroy")
			refreshBalances()
			refreshVehicles()
		end)
	end)
	unit.Parent = current.UnitList
end

refreshVehicles = function()
	if refreshInFlight then
		refreshQueued = true
		return
	end
	refreshInFlight = true
	local response = VehicleManagementRemoteClient.GetState()
	if response.Succeeded and response.State and type(response.State.Vehicles) == "table" then
		clearVehicleCards()
		for _, vehicle in response.State.Vehicles do
			renderVehicleCard(vehicle)
		end
	elseif not response.Succeeded then
		warn("载具列表获取失败：" .. tostring(response.Reason))
	end
	refreshInFlight = false
	if refreshQueued then
		refreshQueued = false
		task.spawn(refreshVehicles)
	end
end

refreshCrates = function()
	if crateRefreshInFlight then
		crateRefreshQueued = true
		return
	end
	crateRefreshInFlight = true
	local response = VehicleCrateRemoteClient.GetState()
	if response.Succeeded and response.State and type(response.State.Crates) == "table" then
		crateState = response.State
		applyFeatureVisibility(response.State.FeatureUnlocked == true)
		clearCrateCards()
		for index, crate in response.State.Crates do
			renderCrateCard(crate, index)
		end

		if not getCrate(crateState, activeCrateId) then
			local firstCrate = response.State.Crates[1]
			if firstCrate and firstCrate.CrateId then
				activeCrateId = firstCrate.CrateId
			end
		end
		applyCrateSelection(activeCrateId)
	elseif not response.Succeeded then
		applyFeatureVisibility(false)
		warn("载具箱子状态获取失败：" .. tostring(response.Reason))
	end
	crateRefreshInFlight = false
	if crateRefreshQueued then
		crateRefreshQueued = false
		task.spawn(refreshCrates)
	end
end

function VehicleUIController.Start()
	if started then
		return
	end
	started = true

	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	playerGui:WaitForChild("HUD", 10)
	playerGui:WaitForChild("Main", 10)
	local resolved, reason = resolveReferences(playerGui)
	if not resolved then
		warn("载具 UI 路径无效：" .. tostring(reason))
		return
	end

	references = resolved
	resolved.Root.Visible = false
	VehicleLotteryPresentationController.Start()
	configureVehicleList()
	applyFeatureVisibility(
		localPlayer:GetAttribute(VehicleCrateProtocol.FeatureUnlockedAttributeName) == true
	)
	NestMapUIController.Start()
	NestMapUIController.SetCallbacks({
		OnExit = function()
			VehicleDeploymentState.Clear()
			applyTabState("Vrhicle")
			setVisible(false)
			task.spawn(function()
				if refreshVehicles then
					refreshVehicles()
				end
			end)
		end,
		OnVehicleStateChanged = function()
			task.spawn(function()
				if refreshVehicles then
					refreshVehicles()
				end
			end)
		end,
	})
	applyTabState(activeTab)
	visibilityGate = LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Gameplay,
		function(nextVisible)
			if references then
				references.Root.Visible = nextVisible
			end
		end,
		false
	)

	refreshBalances()
	localPlayer:GetAttributeChangedSignal(
		DiamondProtocol.BalanceAttributeName
	):Connect(refreshBalances)
	localPlayer:GetAttributeChangedSignal(
		MoneyProtocol.BalanceAttributeName
	):Connect(refreshBalances)
	localPlayer:GetAttributeChangedSignal(
		VehicleCrateProtocol.FeatureUnlockedAttributeName
	):Connect(function()
		applyFeatureVisibility(
			localPlayer:GetAttribute(VehicleCrateProtocol.FeatureUnlockedAttributeName) == true
		)
	end)
	localPlayer:GetAttributeChangedSignal(
		PaidPurchaseProtocol.PaidRandomItemsAllowedAttributeName
	):Connect(function()
		task.spawn(refreshCrates)
	end)
	local paidResultEvent = PaidPurchaseRemoteClient.GetResultEvent()
	paidResultEvent.OnClientEvent:Connect(function(result)
		if type(result) ~= "table"
			or result.Kind ~= PaidPurchaseProtocol.ResultKinds.PurchaseGranted
			or result.ProductKind ~= "VehicleCrate"
		then
			return
		end
		if type(result.CrateId) == "string" then
			crateActionBusy[result.CrateId] = nil
		end
		SoundController.Play("Yes")
		showCratePurchaseResult({ Succeeded = true, Rewards = result.Rewards })
		refreshBalances()
		task.spawn(refreshVehicles)
		task.spawn(refreshCrates)
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(
		finishedPlayer,
		_productId,
		isPurchased
	)
		if finishedPlayer ~= localPlayer or isPurchased then
			return
		end
		table.clear(crateActionBusy)
		task.spawn(refreshCrates)
	end)

	resolved.OpenButton.Activated:Connect(function()
		setVisible(true)
		task.spawn(refreshVehicles)
		task.spawn(refreshCrates)
	end)
	resolved.CloseButton.Activated:Connect(function()
		if activeTab == "Map" then
			applyTabState("Vrhicle")
		end
		setVisible(false)
	end)
	resolved.CrateDropRatesButton.Activated:Connect(showDropRates)
	resolved.CrateDropRatesBackButton.Activated:Connect(showCrateShop)
	for crateId, tab in resolved.CrateTabs do
		local selectedCrateId: CrateId = crateId
		tab.OnButton.Activated:Connect(function()
			selectCrate(selectedCrateId)
		end)
		tab.OffButton.Activated:Connect(function()
			selectCrate(selectedCrateId)
		end)
	end
	task.spawn(refreshVehicles)
	task.spawn(refreshCrates)

	for tabId, tab in resolved.Tabs do
		local selectedTabId: TabId = tabId
		tab.OnButton.Activated:Connect(function()
			applyTabState(selectedTabId)
		end)
		tab.OffButton.Activated:Connect(function()
			applyTabState(selectedTabId)
		end)
	end
end

return VehicleUIController
