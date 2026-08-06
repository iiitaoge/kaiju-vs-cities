--[[
	职责：维护本地玩家 HUD 的现金余额与自动收入总速率。
	输入：Start；余额和总速率来自 Player 上的服务器权威镜像 Attributes。
	输出：HUD.UpData.Money.Val 与 HUD.UpData.Add.Val 的紧凑数字文本。
	内部算法：监听两个 Attribute，并统一使用 CompactNumberFormatter 格式化。
	不负责：计算单栋收入、自动领取、修改余额、创建 HUD 或显示其他玩家数据。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CompactNumberFormatter = require(
	ReplicatedStorage.Shared.UI.CompactNumberFormatter
)
local MoneyProtocol = require(ReplicatedStorage.Shared.Economy.MoneyProtocol)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local LocalUIVisibilityGate = require(script.Parent.LocalUIVisibilityGate)

local EconomyHUDController = {}

type HUDReferences = {
	UpData: GuiObject,
	MoneyValue: TextLabel,
	AutoIncomeValue: TextLabel,
}

local localPlayer = Players.LocalPlayer
local references: HUDReferences? = nil
local visibilityGate: LocalUIVisibilityGate.Handle? = nil
local started = false

local function finiteNonNegative(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
end

local function resolveHUD(playerGui: PlayerGui): (HUDReferences?, string?)
	local hud = playerGui:FindFirstChild("HUD")
	local upData = hud and hud:FindFirstChild("UpData")
	local money = upData and upData:FindFirstChild("Money")
	local add = upData and upData:FindFirstChild("Add")
	local moneyValue = money and money:FindFirstChild("Val")
	local autoIncomeValue = add and add:FindFirstChild("Val")

	if not hud or not hud:IsA("ScreenGui") then
		return nil, "HUDUnavailable"
	end
	if not upData or not upData:IsA("GuiObject") then
		return nil, "UpDataUnavailable"
	end
	if not moneyValue or not moneyValue:IsA("TextLabel") then
		return nil, "MoneyValueUnavailable"
	end
	if not autoIncomeValue or not autoIncomeValue:IsA("TextLabel") then
		return nil, "AutoIncomeValueUnavailable"
	end

	return {
		UpData = upData,
		MoneyValue = moneyValue,
		AutoIncomeValue = autoIncomeValue,
	}, nil
end

local function refreshBalance()
	local current = references
	if not current then
		return
	end
	local balance = localPlayer:GetAttribute(MoneyProtocol.BalanceAttributeName)
	current.MoneyValue.Text = CompactNumberFormatter.Format(
		if finiteNonNegative(balance) then balance else 0
	)
end

local function refreshAutomaticIncome()
	local current = references
	if not current then
		return
	end
	local rate = localPlayer:GetAttribute(
		MoneyProtocol.AutomaticIncomeRateAttributeName
	)
	current.AutoIncomeValue.Text = "+"
		.. CompactNumberFormatter.Format(if finiteNonNegative(rate) then rate else 0)
		.. "/s"
end

function EconomyHUDController.Start()
	if started then
		return
	end
	started = true

	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	playerGui:WaitForChild("HUD", 10)
	local resolved, reason = resolveHUD(playerGui)
	if not resolved then
		warn("经济 HUD 路径无效：" .. tostring(reason))
		return
	end
	references = resolved
	visibilityGate = LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Gameplay,
		function(visible)
			resolved.UpData.Visible = visible
		end,
		resolved.UpData.Visible
	)
	refreshBalance()
	refreshAutomaticIncome()
	localPlayer:GetAttributeChangedSignal(MoneyProtocol.BalanceAttributeName):Connect(
		refreshBalance
	)
	localPlayer:GetAttributeChangedSignal(
		MoneyProtocol.AutomaticIncomeRateAttributeName
	):Connect(refreshAutomaticIncome)
end

return EconomyHUDController
