--[[
	职责：
	- 作为玩家现金余额的唯一物理写入模块。

	输入：
	- Start：无。
	- Get：player。
	- Set：player、有限非负 balance（仅供权威状态恢复）。
	- Add：player、有限非负 amount，用于退款等不属于成长收入的入账。
	- Earn：player、有限非负 amount，同时累计本轮重生收入。
	- TrySpend：player、有限非负 amount。

	输出：
	- Get / Add：操作后的余额。
	- TrySpend：包含 Succeeded、Balance、Reason 的结果。

	读取：
	- PlayerStateService 的 Economy.Money Attribute。

	写入：
	- PlayerStateService 的 Economy.Money Attribute。
	- Player.MoneyBalance Attribute 作为只读客户端镜像，供 UI/按钮刷新。
	- Earn 通过 RebirthStateService 写本轮累计收入。

	不负责：
	- 不计算建筑收入或购买价格。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugLog = require(ReplicatedStorage.Shared.DebugLog)
local MoneyProtocol = require(ReplicatedStorage.Shared.Economy.MoneyProtocol)
local PlayerStateService = require(script.Parent.PlayerStateService)
local RebirthStateService = require(script.Parent.RebirthStateService)

local MoneyService = {}
local log = DebugLog.Create("MoneyService")

export type SpendResult = {
	Succeeded: boolean,
	Balance: number,
	Reason: string?,
}

local function assertAmount(amount: number)
	assert(type(amount) == "number", "amount 必须是 number")
	assert(
		amount == amount and amount < math.huge and amount >= 0,
		"amount 必须是有限非负数"
	)
end

local function initialize(player: Player)
	local economyState = PlayerStateService.GetSection(player, "Economy")
	if economyState:GetAttribute("Money") == nil then
		economyState:SetAttribute("Money", 0)
	end
	player:SetAttribute(MoneyProtocol.BalanceAttributeName, economyState:GetAttribute("Money"))
end

local function write(player: Player, balance: number): number
	PlayerStateService.GetSection(player, "Economy"):SetAttribute("Money", balance)
	player:SetAttribute(MoneyProtocol.BalanceAttributeName, balance)
	return balance
end

function MoneyService.Start()
	Players.PlayerAdded:Connect(initialize)

	for _, player in Players:GetPlayers() do
		initialize(player)
	end
end

function MoneyService.Get(player: Player): number
	local economyState = PlayerStateService.GetSection(player, "Economy")
	return economyState:GetAttribute("Money") or 0
end

function MoneyService.Set(player: Player, balance: number): number
	assertAmount(balance)
	return write(player, balance)
end

function MoneyService.Add(player: Player, amount: number): number
	assertAmount(amount)

	local money = MoneyService.Get(player) + amount
	write(player, money)
	log("Add", player.Name, amount, money)
	return money
end

function MoneyService.Earn(player: Player, amount: number): number
	assertAmount(amount)
	local money = MoneyService.Add(player, amount)
	RebirthStateService.AddRunEarnings(player, amount)
	return money
end

function MoneyService.TrySpend(player: Player, amount: number): SpendResult
	assertAmount(amount)

	local balance = MoneyService.Get(player)
	if balance < amount then
		return {
			Succeeded = false,
			Balance = balance,
			Reason = "InsufficientFunds",
		}
	end

	local newBalance = balance - amount
	write(player, newBalance)
	log("Spend", player.Name, amount, newBalance)
	return {
		Succeeded = true,
		Balance = newBalance,
		Reason = nil,
	}
end

return MoneyService
