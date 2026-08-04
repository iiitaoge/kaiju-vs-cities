--[[
	职责：仅在指定的 Studio 脚本化多人测试中启动正式攻击总验收。
	输入：StudioTestService 的 TestArgument，以及三名本地测试玩家。
	输出：通过 StudioTestService.EndTest 返回成功报告或错误文本。
	内部算法：等待玩家到齐，调用现有 MultiplayerAttackAcceptanceSpec，并结束整个测试会话。
	不负责：修改正式攻击逻辑、创建测试玩家、决定正式服务器人数或在已发布服务器运行。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MultiplayerAttackAcceptanceSpec = require(
	script.Parent.MultiplayerAttackAcceptanceSpec
)
local MultiplayerAttackAcceptanceProtocol = require(
	ReplicatedStorage.Shared.Test.MultiplayerAttackAcceptanceProtocol
)

if not RunService:IsStudio() then
	return
end

local StudioTestService = game:GetService("StudioTestService")
local TEST_ARGUMENT_WAIT_TIMEOUT_SECONDS = 10
local PLAYER_WAIT_TIMEOUT_SECONDS = 30

local function waitForMatchingTestArgument(): boolean
	local deadline = os.clock() + TEST_ARGUMENT_WAIT_TIMEOUT_SECONDS
	repeat
		local argument = StudioTestService:GetTestArgs()
		if argument ~= nil then
			return argument == MultiplayerAttackAcceptanceProtocol.TestArgument
		end
		task.wait(0.05)
	until os.clock() >= deadline
	return false
end

if not waitForMatchingTestArgument() then
	return
end

print("CODEX_MULTIPLAYER_ATTACK_SERVER_BOOTSTRAP_READY")

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
		if #players == MultiplayerAttackAcceptanceProtocol.RequiredPlayerCount then
			return players
		end
		task.wait(0.1)
	until os.clock() >= deadline

	error(string.format(
		"等待 %d 名多人验收玩家超时；当前 %d 名",
		MultiplayerAttackAcceptanceProtocol.RequiredPlayerCount,
		#Players:GetPlayers()
	))
end

local succeeded, reportOrError = xpcall(function()
	return MultiplayerAttackAcceptanceSpec.Run(waitForPlayers())
end, debug.traceback)

if succeeded then
	print("CODEX_MULTIPLAYER_ATTACK_ACCEPTANCE_OK")
	StudioTestService:EndTest({
		Succeeded = true,
		Test = MultiplayerAttackAcceptanceProtocol.TestArgument,
		Report = reportOrError,
	})
else
	warn("CODEX_MULTIPLAYER_ATTACK_ACCEPTANCE_FAILED\n" .. tostring(reportOrError))
	StudioTestService:EndTest({
		Succeeded = false,
		Test = MultiplayerAttackAcceptanceProtocol.TestArgument,
		Error = tostring(reportOrError),
	})
end
