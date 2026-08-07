--[[
	职责：隔离项目业务代码与官方 GameAnalytics SDK。
	输入：Start 从 ServerStorage.GameAnalytics Attributes 读取凭据；事件函数接收已裁决的服务器事实。
	输出：返回事件是否已交给 SDK 队列；缺凭据、参数无效或 SDK 异常时返回 false。
	内部算法：校验配置 → 延迟 require SDK → 初始化白名单/Build → 保护调用事件接口。
	不负责：判断业务成功、聚合高频事件、计算金额、创建 Roblox 漏斗或重试网络请求。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameAnalyticsConfig = require(script.Parent.GameAnalyticsConfig)

local GameAnalyticsGateway = {}

export type ResourceFlow = "Source" | "Sink"
export type ProgressionStatus = "Start" | "Complete" | "Fail"

local started = false
local enabled = false
local sdk = nil

local function getConfigFolder(): Folder?
	local instance = ServerStorage:FindFirstChild(GameAnalyticsConfig.ConfigFolderName)
	if instance and instance:IsA("Folder") then
		return instance
	end
	return nil
end

local function isCredential(value, expectedLength: number): boolean
	return type(value) == "string"
		and #value == expectedLength
		and string.find(value, "^[A-Za-z0-9]+$") ~= nil
end

local function resolveBuild(configFolder: Folder): string
	local value = configFolder:GetAttribute(GameAnalyticsConfig.BuildAttribute)
	if type(value) == "string" and value ~= "" and #value <= 32 then
		return value
	end
	return GameAnalyticsConfig.DefaultBuild
end

function GameAnalyticsGateway.Start(): boolean
	if started then
		return enabled
	end
	started = true
	ReplicatedStorage:SetAttribute(GameAnalyticsConfig.ClientEnabledAttribute, false)

	local configFolder = getConfigFolder()
	if not configFolder then
		warn(string.format(
			"GameAnalytics 未启用：请在 ServerStorage 下创建 Folder %s，并设置有效的凭据 Attributes",
			GameAnalyticsConfig.ConfigFolderName
		))
		return false
	end

	local gameKey = configFolder:GetAttribute(GameAnalyticsConfig.GameKeyAttribute)
	local secretKey = configFolder:GetAttribute(GameAnalyticsConfig.SecretKeyAttribute)
	if not isCredential(gameKey, 32) or not isCredential(secretKey, 40) then
		warn(string.format(
			"GameAnalytics 未启用：请在 ServerStorage.%s 设置有效的 %s 和 %s Attributes",
			GameAnalyticsConfig.ConfigFolderName,
			GameAnalyticsConfig.GameKeyAttribute,
			GameAnalyticsConfig.SecretKeyAttribute
		))
		return false
	end

	local loaded, sdkOrError = pcall(function()
		return require(ReplicatedStorage.Shared.Vendor.GameAnalytics)
	end)
	if not loaded then
		warn("加载 GameAnalytics SDK 失败：" .. tostring(sdkOrError))
		return false
	end

	local initialized, initializeError = pcall(function()
		sdkOrError:initialize({
			gameKey = gameKey,
			secretKey = secretKey,
			build = resolveBuild(configFolder),
			availableResourceCurrencies = { GameAnalyticsConfig.Currency },
			availableResourceItemTypes = GameAnalyticsConfig.ResourceItemTypes,
			enableInfoLog = configFolder:GetAttribute(GameAnalyticsConfig.DebugAttribute) == true,
			enableVerboseLog = false,
			automaticSendBusinessEvents = false,
			reportErrors = false,
			useCustomUserId = false,
		})
	end)
	if not initialized then
		warn("初始化 GameAnalytics SDK 失败：" .. tostring(initializeError))
		return false
	end

	sdk = sdkOrError
	enabled = true
	ReplicatedStorage:SetAttribute(GameAnalyticsConfig.ClientEnabledAttribute, true)
	return true
end

function GameAnalyticsGateway.IsEnabled(): boolean
	return enabled
end

function GameAnalyticsGateway.LogDesign(
	player: Player,
	eventId: string,
	value: number?,
	customFields: { [string]: any }?
): boolean
	if not enabled
		or not sdk
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or type(eventId) ~= "string"
		or eventId == ""
	then
		return false
	end
	if value ~= nil
		and (type(value) ~= "number" or value ~= value or math.abs(value) == math.huge)
	then
		return false
	end

	local succeeded = pcall(function()
		sdk:addDesignEvent(player.UserId, {
			eventId = eventId,
			value = value,
			customFields = customFields,
		})
	end)
	return succeeded
end

function GameAnalyticsGateway.LogResource(
	player: Player,
	flow: ResourceFlow,
	amount: number,
	itemType: string,
	itemId: string,
	customFields: { [string]: any }?
): boolean
	if not enabled
		or not sdk
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or (flow ~= "Source" and flow ~= "Sink")
		or type(amount) ~= "number"
		or amount ~= amount
		or amount == math.huge
		or amount <= 0
		or type(itemType) ~= "string"
		or itemType == ""
		or type(itemId) ~= "string"
		or itemId == ""
	then
		return false
	end

	local flowType = if flow == "Source"
		then sdk.EGAResourceFlowType.Source
		else sdk.EGAResourceFlowType.Sink
	local succeeded = pcall(function()
		sdk:addResourceEvent(player.UserId, {
			flowType = flowType,
			currency = GameAnalyticsConfig.Currency,
			amount = amount,
			itemType = itemType,
			itemId = itemId,
			customFields = customFields,
		})
	end)
	return succeeded
end

function GameAnalyticsGateway.LogProgression(
	player: Player,
	status: ProgressionStatus,
	progression01: string,
	progression02: string?,
	progression03: string?,
	score: number?,
	customFields: { [string]: any }?
): boolean
	if not enabled
		or not sdk
		or typeof(player) ~= "Instance"
		or not player:IsA("Player")
		or (status ~= "Start" and status ~= "Complete" and status ~= "Fail")
		or type(progression01) ~= "string"
		or progression01 == ""
		or (progression02 ~= nil
			and (type(progression02) ~= "string" or progression02 == ""))
		or (progression03 ~= nil
			and (type(progression03) ~= "string" or progression03 == ""))
		or (progression03 ~= nil and progression02 == nil)
		or (score ~= nil
			and (type(score) ~= "number"
				or score ~= score
				or math.abs(score) == math.huge))
	then
		return false
	end

	local progressionStatus = if status == "Start"
		then sdk.EGAProgressionStatus.Start
		else if status == "Complete"
			then sdk.EGAProgressionStatus.Complete
			else sdk.EGAProgressionStatus.Fail
	local succeeded = pcall(function()
		sdk:addProgressionEvent(player.UserId, {
			progressionStatus = progressionStatus,
			progression01 = progression01,
			progression02 = progression02,
			progression03 = progression03,
			score = score,
			customFields = customFields,
		})
	end)
	return succeeded
end

return GameAnalyticsGateway
