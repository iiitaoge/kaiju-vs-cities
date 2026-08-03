--[[
	职责：仅在指定的 Studio 脚本化多人测试中启动八人容量验收。
	输入：StudioTestService TestArgument，以及八名本地测试玩家。
	输出：通过 StudioTestService.EndTest 返回成功报告或错误文本。
	内部算法：等待测试参数和玩家到齐，调用 EightPlayerCapacityAcceptanceSpec 后结束会话。
	不负责：修改正式玩法、设置体验 MaxPlayers 或发布 Place。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StudioTestService = game:GetService("StudioTestService")

local EightPlayerCapacityAcceptanceSpec = require(
	script.Parent.EightPlayerCapacityAcceptanceSpec
)
local Protocol = require(
	ReplicatedStorage.Shared.Test.EightPlayerCapacityAcceptanceProtocol
)

if not RunService:IsStudio() then
	return
end

local TEST_ARGUMENT_WAIT_TIMEOUT_SECONDS = 10
local PLAYER_WAIT_TIMEOUT_SECONDS = 30

local function waitForMatchingTestArgument(): boolean
	local deadline = os.clock() + TEST_ARGUMENT_WAIT_TIMEOUT_SECONDS
	repeat
		local argument = StudioTestService:GetTestArgs()
		if argument ~= nil then
			return argument == Protocol.TestArgument
		end
		task.wait(0.05)
	until os.clock() >= deadline
	return false
end

if not waitForMatchingTestArgument() then
	return
end

print("CODEX_EIGHT_PLAYER_CAPACITY_SERVER_BOOTSTRAP_READY")

local function sortedPlayers(): { Player }
	local result = Players:GetPlayers()
	table.sort(result, function(a, b)
		return a.UserId < b.UserId
	end)
	return result
end

local function waitForPlayers(): { Player }
	local deadline = os.clock() + PLAYER_WAIT_TIMEOUT_SECONDS
	repeat
		local players = sortedPlayers()
		if #players == Protocol.RequiredPlayerCount then
			return players
		end
		task.wait(0.1)
	until os.clock() >= deadline

	error(string.format(
		"等待 %d 名容量验收玩家超时；当前 %d 名",
		Protocol.RequiredPlayerCount,
		#Players:GetPlayers()
	))
end

local succeeded, reportOrError = xpcall(function()
	return EightPlayerCapacityAcceptanceSpec.Run(waitForPlayers())
end, debug.traceback)

if succeeded then
	print("CODEX_EIGHT_PLAYER_CAPACITY_OK")
	StudioTestService:EndTest({
		Succeeded = true,
		Test = Protocol.TestArgument,
		Report = reportOrError,
	})
else
	warn("CODEX_EIGHT_PLAYER_CAPACITY_FAILED\n" .. tostring(reportOrError))
	StudioTestService:EndTest({
		Succeeded = false,
		Test = Protocol.TestArgument,
		Error = tostring(reportOrError),
	})
end
