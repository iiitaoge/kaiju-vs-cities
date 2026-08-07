--[[
	职责：作为玩家钻石余额的唯一物理写入模块。
	输入：Start 无参数；Get/Set/Add/TrySpend 接收 player 和对应金额。
	输出：余额读写结果；Player.DiamondBalance 是客户端只读镜像。
	内部算法：ServerStorage 运行时 Economy.Diamond Attribute 作为权威值，写入时同步玩家镜像。
	不负责：奖励配置、七日倒计时、DataStore、UI 或消费资格判断。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiamondProtocol = require(ReplicatedStorage.Shared.Economy.DiamondProtocol)
local PlayerStateService = require(script.Parent.PlayerStateService)

local DiamondService = {}

export type SpendResult = {
	Succeeded: boolean,
	Balance: number,
	Reason: string?,
}

local DEFAULT_BALANCE = 0
local started = false

local function assertAmount(amount: number)
	assert(type(amount) == "number", "amount 必须是 number")
	assert(
		amount == amount and amount < math.huge and amount >= 0,
		"amount 必须是有限非负数"
	)
end

local function initialize(player: Player)
	local economyState = PlayerStateService.GetSection(player, "Economy")
	if economyState:GetAttribute("Diamond") == nil then
		economyState:SetAttribute("Diamond", DEFAULT_BALANCE)
	end
	player:SetAttribute(
		DiamondProtocol.BalanceAttributeName,
		economyState:GetAttribute("Diamond")
	)
end

local function write(player: Player, balance: number): number
	PlayerStateService.GetSection(player, "Economy"):SetAttribute("Diamond", balance)
	player:SetAttribute(DiamondProtocol.BalanceAttributeName, balance)
	return balance
end

function DiamondService.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(initialize)
	for _, player in Players:GetPlayers() do
		initialize(player)
	end
end

function DiamondService.Get(player: Player): number
	local economyState = PlayerStateService.GetSection(player, "Economy")
	return economyState:GetAttribute("Diamond") or DEFAULT_BALANCE
end

function DiamondService.Set(player: Player, balance: number): number
	assertAmount(balance)
	return write(player, balance)
end

function DiamondService.Add(player: Player, amount: number): number
	assertAmount(amount)
	return write(player, DiamondService.Get(player) + amount)
end

function DiamondService.TrySpend(player: Player, amount: number): SpendResult
	assertAmount(amount)

	local balance = DiamondService.Get(player)
	if balance < amount then
		return {
			Succeeded = false,
			Balance = balance,
			Reason = "InsufficientDiamonds",
		}
	end

	local newBalance = balance - amount
	write(player, newBalance)
	return {
		Succeeded = true,
		Balance = newBalance,
		Reason = nil,
	}
end

return DiamondService
