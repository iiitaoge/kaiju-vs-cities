--[[
	职责：维护本地玩家 HUD 的现金余额与自动收入总速率。
	输入：Start；余额来自 Player.MoneyBalance，收入来自自有运行时房屋的 UI 镜像 Attributes。
	输出：HUD.UpData.Money.Val 与 HUD.UpData.Add.Val 的紧凑数字文本。
	内部算法：监听余额；汇总所有 Alive 且开启 AutoIncome 的自有房屋 IncomePerSecond。
	不负责：计算单栋收入、自动领取、修改余额、创建 HUD 或显示其他玩家数据。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayerCityRuntimeAccess = require(
	script.Parent.Parent.Building.LocalPlayerCityRuntimeAccess
)
local IncomeHouseWorldUIProtocol = require(
	ReplicatedStorage.Shared.Building.IncomeHouseWorldUIProtocol
)
local MoneyProtocol = require(ReplicatedStorage.Shared.Economy.MoneyProtocol)
local RuntimeBuildingIdentity = require(
	ReplicatedStorage.Shared.Building.RuntimeBuildingIdentity
)

local EconomyHUDController = {}

type HUDReferences = {
	MoneyValue: TextLabel,
	AutoIncomeValue: TextLabel,
}

local localPlayer = Players.LocalPlayer
local modelConnections: { [Model]: { RBXScriptConnection } } = setmetatable(
	{},
	{ __mode = "k" }
)
local references: HUDReferences? = nil
local started = false

local function finiteNonNegative(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
end

local function formatPlainNumber(value: number): string
	local rounded = math.round(value)
	if math.abs(value - rounded) < 1e-6 then
		return string.format("%.0f", value)
	end
	return (string.format("%.2f", value):gsub("(%..-)0+$", "%1"):gsub("%.$", ""))
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
	current.MoneyValue.Text = formatPlainNumber(
		if finiteNonNegative(balance) then balance else 0
	)
end

local function getAutomaticIncomeRate(model: Model): number
	local identity = RuntimeBuildingIdentity.Read(model)
	if not identity or identity.OwnerUserId ~= localPlayer.UserId then
		return 0
	end
	if model:GetAttribute(IncomeHouseWorldUIProtocol.LifeStateAttributeName) ~= "Alive"
		or model:GetAttribute(IncomeHouseWorldUIProtocol.AutoIncomeAttributeName) ~= true
	then
		return 0
	end

	local rate = model:GetAttribute(
		IncomeHouseWorldUIProtocol.IncomePerSecondAttributeName
	)
	return if finiteNonNegative(rate) then rate else 0
end

local function refreshAutomaticIncome()
	local current = references
	if not current then
		return
	end
	local total = 0
	for model in modelConnections do
		total += getAutomaticIncomeRate(model)
	end
	current.AutoIncomeValue.Text = "+" .. formatPlainNumber(total) .. "/s"
end

local function unbindModel(model: Model)
	local connections = modelConnections[model]
	modelConnections[model] = nil
	if not connections then
		return
	end
	for _, connection in connections do
		connection:Disconnect()
	end
end

local function bindModel(model: Model)
	if modelConnections[model] then
		return
	end
	local connections = {}
	modelConnections[model] = connections

	for _, attributeName in {
		IncomeHouseWorldUIProtocol.LifeStateAttributeName,
		IncomeHouseWorldUIProtocol.AutoIncomeAttributeName,
		IncomeHouseWorldUIProtocol.IncomePerSecondAttributeName,
	} do
		table.insert(
			connections,
			model:GetAttributeChangedSignal(attributeName):Connect(refreshAutomaticIncome)
		)
	end
end

local function attachBuildings()
	local plot = LocalPlayerCityRuntimeAccess.WaitForPlot(localPlayer.UserId, 10)
	if not plot then
		warn("经济 HUD 找不到本地玩家 Plot")
		return
	end
	local runtime = plot:WaitForChild("Runtime", 10)
	local buildings = runtime and runtime:WaitForChild("Buildings", 10)
	if not buildings or not buildings:IsA("Folder") then
		warn("经济 HUD 找不到自有运行时建筑目录")
		return
	end

	for _, child in buildings:GetChildren() do
		if child:IsA("Model") then
			bindModel(child)
		end
	end
	buildings.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			bindModel(child)
			refreshAutomaticIncome()
		end
	end)
	buildings.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			unbindModel(child)
			refreshAutomaticIncome()
		end
	end)
	refreshAutomaticIncome()
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
	refreshBalance()
	refreshAutomaticIncome()
	localPlayer:GetAttributeChangedSignal(MoneyProtocol.BalanceAttributeName):Connect(
		refreshBalance
	)
	task.spawn(attachBuildings)
end

return EconomyHUDController
