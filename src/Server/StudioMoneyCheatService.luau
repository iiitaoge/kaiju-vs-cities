--[[
	职责：仅在 Studio 中注册 /money 聊天作弊并给指令发起者增加现金。
	输入：Start；运行时接收 TextChatCommand 的 TextSource 与完整聊天文本。
	输出：合法指令通过 MoneyService 更新玩家余额；非法指令仅产生服务端警告。
	内部算法：创建 Studio 专用 TextChatCommand → 解析金额 → 查找发起玩家 → 检查余额不会溢出 → 入账。
	不负责：正式服管理权限、聊天 UI 反馈、金额格式规则或现金底层存储。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local MoneyCheatCommandRules = require(
	ReplicatedStorage.Shared.Cheat.MoneyCheatCommandRules
)
local MoneyService = require(script.Parent.MoneyService)

local StudioMoneyCheatService = {}

local started = false

local function onTriggered(originTextSource: TextSource, unfilteredText: string)
	local amount = MoneyCheatCommandRules.ParseAmount(unfilteredText)
	if amount == nil then
		warn(string.format("[StudioMoneyCheatService] 非法指令：%q", unfilteredText))
		return
	end

	local player = Players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		warn("[StudioMoneyCheatService] 找不到指令发起玩家")
		return
	end

	local balance = MoneyService.Get(player)
	if balance + amount >= math.huge then
		warn("[StudioMoneyCheatService] 加钱后余额不是有限数")
		return
	end

	MoneyService.Add(player, amount)
end

function StudioMoneyCheatService.Start()
	if started or not RunService:IsStudio() then
		return
	end
	started = true

	local command = Instance.new("TextChatCommand")
	command.Name = "StudioMoneyCommand"
	command.PrimaryAlias = "/money"
	command.Triggered:Connect(onTriggered)
	command.Parent = TextChatService
end

return StudioMoneyCheatService
