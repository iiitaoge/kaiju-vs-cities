--[[
	职责：在防守方显示 PopUp.InCombat，并把出征开始通知显示为倒计时进度条。

	输入：服务器发给防守方的 ExpeditionStarted/ExpeditionEnded command。
	输出：出征开始时显示 InCombat 与满格 Bar；Bar 按服务器时间递减到 0，结束后隐藏进度条。
	内部算法：每帧使用 workspace:GetServerTimeNow() 计算
	clamp(1 - (now - StartedAt) / ExpeditionDuration, 0, 1)，只改 Bar.Size 的 X 分量；
	决斗按钮 Check 的显隐继续由 MonsterDuelWatchButtonController 负责。
	不负责：启动出征、修改服务器计时、判断攻击结果或控制 Check 按钮。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MonsterExpeditionProgressRemoteClient = require(
	script.Parent.MonsterExpeditionProgressRemoteClient
)
local MonsterExpeditionProgressProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionProgressProtocol
)
local MonsterExpeditionTimingConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionTimingConfigs
)
local LocalCombatVisibilityService = require(
	script.Parent.Parent.UI.LocalCombatVisibilityService
)

local MonsterExpeditionProgressUIController = {}

type References = {
	Root: GuiObject,
	ProgressBar: GuiObject,
	Bar: GuiObject,
	Check: GuiObject?,
}

type ActiveRun = {
	CommandId: number,
	AttackerUserId: number,
	AttackerSpawnPointId: string,
	StartedAt: number,
	PreviousRootVisible: boolean,
}

local started = false
local references: References? = nil
local fullBarSize: UDim2? = nil
local activeRun: ActiveRun? = nil
local pendingCommand = nil

local function isFiniteNumber(value): boolean
	return type(value) == "number"
		and value == value
		and math.abs(value) < math.huge
end

local function findGuiObject(parent: Instance?, name: string): GuiObject?
	local child = parent and parent:FindFirstChild(name)
	return if child and child:IsA("GuiObject") then child else nil
end

local function resolve(playerGui: PlayerGui): References?
	local popup = playerGui:FindFirstChild("PopUp")
	local inCombat = findGuiObject(popup, "InCombat")
	local progressBar = findGuiObject(inCombat, "ProgressBar")
	local bar = findGuiObject(progressBar, "Bar")
	if not inCombat or not progressBar or not bar then
		return nil
	end
	return {
		Root = inCombat,
		ProgressBar = progressBar,
		Bar = bar,
		Check = findGuiObject(inCombat, "Check"),
	}
end

local function waitForReferences(playerGui: PlayerGui): (References?, string?)
	local deadline = os.clock() + 10
	repeat
		local resolved = resolve(playerGui)
		if resolved then
			return resolved, nil
		end
		if os.clock() >= deadline then
			return nil, "InCombatProgressBarUnavailable"
		end
		task.wait()
	until false
end

local function setRatio(ratio: number)
	local currentReferences = references
	local baseSize = fullBarSize
	if not currentReferences or not baseSize then
		return
	end

	ratio = math.clamp(ratio, 0, 1)
	currentReferences.Bar.Size = UDim2.new(
		baseSize.X.Scale * ratio,
		baseSize.X.Offset * ratio,
		baseSize.Y.Scale,
		baseSize.Y.Offset
	)
end

local function isSameExpedition(
	run: ActiveRun,
	command: MonsterExpeditionProgressProtocol.Command
): boolean
	return run.CommandId == command.CommandId
		and run.AttackerUserId == command.AttackerUserId
		and run.AttackerSpawnPointId == command.AttackerSpawnPointId
end

local function stop()
	local run = activeRun
	if not run then
		LocalCombatVisibilityService.SetActive(false)
		return
	end
	activeRun = nil
	LocalCombatVisibilityService.SetActive(false)

	local currentReferences = references
	if not currentReferences then
		return
	end
	currentReferences.ProgressBar.Visible = false
	currentReferences.Bar.Visible = false
	setRatio(1)
	if not currentReferences.Check or not currentReferences.Check.Visible then
		currentReferences.Root.Visible = run.PreviousRootVisible
	end
end

local function start(command: MonsterExpeditionProgressProtocol.StartedCommand)
	if not isFiniteNumber(command.StartedAt) then
		return
	end

	local currentReferences = references
	local baseSize = fullBarSize
	if not currentReferences or not baseSize then
		pendingCommand = command
		LocalCombatVisibilityService.SetActive(true)
		return
	end

	stop()
	activeRun = {
		CommandId = command.CommandId,
		AttackerUserId = command.AttackerUserId,
		AttackerSpawnPointId = command.AttackerSpawnPointId,
		StartedAt = command.StartedAt,
		PreviousRootVisible = currentReferences.Root.Visible,
	}
	LocalCombatVisibilityService.SetActive(true)

	currentReferences.Root.Visible = true
	currentReferences.ProgressBar.Visible = true
	currentReferences.Bar.Visible = true
	setRatio(1)
end

local function handleCommand(command: MonsterExpeditionProgressProtocol.Command)
	if command.Kind == MonsterExpeditionProgressProtocol.StartedKind then
		start(command)
		return
	end

	pendingCommand = nil
	local run = activeRun
	if run and isSameExpedition(run, command) then
		stop()
	elseif not run then
		LocalCombatVisibilityService.SetActive(false)
	end
end

function MonsterExpeditionProgressUIController.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		MonsterExpeditionProgressRemoteClient.Observe(handleCommand)
	end)

	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
		local resolved, reason = waitForReferences(playerGui)
		if not resolved then
			warn("防守方出征进度条 UI 初始化失败：" .. tostring(reason))
			return
		end

		references = resolved
		fullBarSize = resolved.Bar.Size
		resolved.ProgressBar.Visible = false
		resolved.Bar.Visible = false

		RunService.RenderStepped:Connect(function()
			local run = activeRun
			if not run then
				return
			end

			local duration = MonsterExpeditionTimingConfigs.ExpeditionDuration
			local ratio = if duration > 0
				then 1 - (Workspace:GetServerTimeNow() - run.StartedAt) / duration
				else 0
			setRatio(ratio)
			if ratio <= 0 then
				stop()
			end
		end)

		local queuedCommand = pendingCommand
		pendingCommand = nil
		if queuedCommand
			and queuedCommand.Kind == MonsterExpeditionProgressProtocol.StartedKind
		then
			start(queuedCommand)
		end
	end)
end

return MonsterExpeditionProgressUIController
