--[[
	职责：在服务器成功启用 GA 后初始化官方 SDK 的客户端平台回调。
	输入：Start 无参数；观察 ReplicatedStorage.GameAnalyticsEnabled Attribute。
	输出：返回本次是否初始化成功；未启用时返回 false 并等待服务器启用信号。
	内部算法：只注册一次 → Attribute 为 true 时 require 共享 SDK → pcall initClient。
	不负责：发送业务事件、读取凭据、判断玩家加载完成或接受客户端自定义埋点。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAnalyticsClientService = {}

local started = false
local initializationAttempted = false
local initialized = false
local enabledConnection: RBXScriptConnection? = nil

local function tryInitialize(): boolean
	if initializationAttempted
		or ReplicatedStorage:GetAttribute("GameAnalyticsEnabled") ~= true
	then
		return initialized
	end
	initializationAttempted = true
	if enabledConnection then
		enabledConnection:Disconnect()
		enabledConnection = nil
	end

	local succeeded, errorValue = pcall(function()
		local GameAnalytics = require(ReplicatedStorage.Shared.Vendor.GameAnalytics)
		GameAnalytics.initClient()
	end)
	if not succeeded then
		warn("初始化 GameAnalytics 客户端失败：" .. tostring(errorValue))
	end
	initialized = succeeded
	return succeeded
end

function GameAnalyticsClientService.Start(): boolean
	if started then
		return initialized
	end
	started = true
	if tryInitialize() then
		return true
	end
	enabledConnection = ReplicatedStorage:GetAttributeChangedSignal(
		"GameAnalyticsEnabled"
	):Connect(tryInitialize)
	return false
end

return GameAnalyticsClientService
