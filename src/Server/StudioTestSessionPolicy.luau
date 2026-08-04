--[[
	职责：识别会修改玩法状态的 Studio 脚本化验收会话。
	输入：纯函数接收 TestArgument；运行时查询读取 StudioTestService 当前参数。
	输出：本会话是否必须禁用真实玩家存档读写。
	内部算法：仅允许已登记的多人验收参数命中；普通 Studio Play 和正式服均不命中。
	不负责：加载默认状态、DataStore、启动测试或结束测试。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StudioTestService = game:GetService("StudioTestService")

local EightPlayerCapacityAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.EightPlayerCapacityAcceptanceProtocol
)
local MultiplayerAttackAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.MultiplayerAttackAcceptanceProtocol
)

local StudioTestSessionPolicy = {}

local persistenceDisabledArguments = table.freeze({
	[EightPlayerCapacityAcceptanceProtocol.TestArgument] = true,
	[MultiplayerAttackAcceptanceProtocol.TestArgument] = true,
})

function StudioTestSessionPolicy.IsPersistenceDisabledForArgument(argument): boolean
	return type(argument) == "string" and persistenceDisabledArguments[argument] == true
end

function StudioTestSessionPolicy.ShouldDisablePersistence(): boolean
	if not RunService:IsStudio() then
		return false
	end
	local succeeded, argument = pcall(StudioTestService.GetTestArgs, StudioTestService)
	return succeeded
		and StudioTestSessionPolicy.IsPersistenceDisabledForArgument(argument)
end

return table.freeze(StudioTestSessionPolicy)
