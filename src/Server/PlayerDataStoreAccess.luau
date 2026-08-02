--[[
	职责：封装玩家存档的一次 DataStore 读写。
	输入：Load 接收 UserId；Save 接收 UserId 和可序列化存档表。
	输出：Succeeded、Value/Reason；所有 Roblox API 异常都被转换为稳定结果。
	内部算法：Studio 与线上使用不同 Store；保存采用 UpdateAsync 覆盖当前玩家键。
	不负责：Schema、状态快照、重试队列、自动保存或玩家生命周期。
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Configs = require(script.Parent.PlayerPersistenceConfigs)

local PlayerDataStoreAccess = {}

local function isEnabled(): boolean
	return not RunService:IsStudio() or Configs.StudioEnabled
end

local function getStore()
	local storeName = if RunService:IsStudio()
		then Configs.StudioStoreName
		else Configs.ProductionStoreName
	return DataStoreService:GetDataStore(storeName)
end

local function getKey(userId: number): string
	assert(type(userId) == "number" and userId % 1 == 0, "userId 必须是整数")
	return Configs.KeyPrefix .. tostring(userId)
end

function PlayerDataStoreAccess.IsEnabled(): boolean
	return isEnabled()
end

function PlayerDataStoreAccess.Load(userId: number)
	if not isEnabled() then
		return { Succeeded = false, Value = nil, Reason = "PersistenceDisabled" }
	end
	local succeeded, value = pcall(function()
		return getStore():GetAsync(getKey(userId))
	end)
	if not succeeded then
		return { Succeeded = false, Value = nil, Reason = tostring(value) }
	end
	return { Succeeded = true, Value = value, Reason = nil }
end

function PlayerDataStoreAccess.Save(userId: number, data)
	if not isEnabled() then
		return { Succeeded = false, Reason = "PersistenceDisabled" }
	end
	local succeeded, failure = pcall(function()
		getStore():UpdateAsync(getKey(userId), function()
			return data
		end)
	end)
	if not succeeded then
		return { Succeeded = false, Reason = tostring(failure) }
	end
	return { Succeeded = true, Reason = nil }
end

return PlayerDataStoreAccess
