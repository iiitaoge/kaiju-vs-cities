--[[
	职责：当当前任务只差执行区域解锁时，把玩家引导到对应的世界解锁按钮。
	输入：TaskPresentation 快照、当前玩家 Plot 和任务配置。
	输出：复用 TutorialPresentation 的世界 Beam 与 HUD.Guide 小手；任务未达到解锁前置、
	解锁按钮不存在或区域已解锁时隐藏。
	内部算法：当前快照进度达到 Target 后，从任务要求读取 ZoneId，查找玩家 Plot 中的
	<ZoneId>-Unlock-Button，并把按钮的 BasePart 交给箭头表现；金币余额不参与显示判定。
	不负责：任务进度计算、区域解锁权限、金币校验、按钮点击或奖励发放。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayerPlotAccess = require(script.Parent.Parent.LocalPlayerPlotAccess)
local LocalPlotButtonAccess = require(
	script.Parent.Parent.Button.LocalPlotButtonAccess
)
local TutorialPresentation = require(
	script.Parent.Parent.Tutorial.TutorialPresentation
)
local TaskConfigs = require(ReplicatedStorage.Shared.Task.TaskConfigs)
local TaskPresentationProtocol = require(
	ReplicatedStorage.Shared.Task.TaskPresentationProtocol
)
local TaskProtocol = require(ReplicatedStorage.Shared.Task.TaskProtocol)

local TaskGuideController = {}

local POLL_SECONDS = 0.35
local localPlayer = Players.LocalPlayer
local started = false
local queryRemote: RemoteFunction? = nil
local presentation: TutorialPresentation.Handle? = nil
local pendingSnapshot: TaskPresentationProtocol.Snapshot? = nil
local currentTarget: BasePart? = nil

local GUIDE_DEFINITION = table.freeze({
	Title = "",
	Info = "",
	TargetKind = nil,
})

local function findModelPart(model: Model?): BasePart?
	if not model then
		return nil
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local pull = model:FindFirstChild("Pull", true)
	if pull and pull:IsA("BasePart") then
		return pull
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getRemotes(): (RemoteFunction?, RemoteEvent?)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes or not remotes:IsA("Folder") then
		return nil, nil
	end
	local query = remotes:WaitForChild(
		TaskPresentationProtocol.QueryRemoteName,
		10
	)
	local taskPresentation = remotes:WaitForChild(
		TaskPresentationProtocol.RemoteName,
		10
	)
	if not query or not query:IsA("RemoteFunction") then
		return nil, nil
	end
	if not taskPresentation or not taskPresentation:IsA("RemoteEvent") then
		return nil, nil
	end
	return query, taskPresentation
end

local function getUnlockZoneId(snapshot: TaskPresentationProtocol.Snapshot): string?
	if not snapshot.Visible
		or not snapshot.TaskId
		or snapshot.Current == nil
		or snapshot.Target == nil
		or snapshot.Current < snapshot.Target
	then
		return nil
	end

	local taskDefinition = TaskConfigs.Tasks[snapshot.TaskId]
	if not taskDefinition then
		return nil
	end
	for _, requirement in taskDefinition.Requirements do
		if requirement.Kind == TaskProtocol.RequirementKinds.UnlockZone then
			local zoneId = requirement.Config.ZoneId
			if type(zoneId) == "string" and zoneId ~= "" then
				return zoneId
			end
		end
	end
	return nil
end

local function resolveTarget(snapshot: TaskPresentationProtocol.Snapshot): BasePart?
	local zoneId = getUnlockZoneId(snapshot)
	if not zoneId then
		return nil
	end

	local plot = LocalPlayerPlotAccess.Find(localPlayer.UserId)
	local button = if plot
		then LocalPlotButtonAccess.FindInPlot(
			plot,
			zoneId,
			zoneId .. "-Unlock-Button"
		)
		else nil
	return findModelPart(button)
end

local function applySnapshot()
	local currentPresentation = presentation
	if not currentPresentation then
		return
	end

	local target = if pendingSnapshot
		then resolveTarget(pendingSnapshot)
		else nil
	if target then
		currentTarget = target
		currentPresentation.Show(GUIDE_DEFINITION, {
			GuiObject = nil,
			WorldPart = target,
			WorldPosition = target.Position,
			WorldBounds = nil,
			ScreenCenter = nil,
		})
	elseif currentTarget ~= nil then
		currentTarget = nil
		currentPresentation.Hide()
	end
end

local function receiveSnapshot(snapshot): boolean
	local valid, reason = TaskPresentationProtocol.Validate(snapshot)
	if not valid then
		warn("拒绝无效任务解锁引导快照：" .. tostring(reason))
		return false
	end
	pendingSnapshot = snapshot
	applySnapshot()
	return true
end

local function refreshState()
	local remote = queryRemote
	if not remote then
		return
	end

	local succeeded, response = pcall(function()
		return remote:InvokeServer(TaskPresentationProtocol.RequestKinds.GetState)
	end)
	if not succeeded or type(response) ~= "table" then
		warn("任务解锁引导状态请求失败：" .. tostring(response))
		return
	end
	if response.Snapshot then
		receiveSnapshot(response.Snapshot)
	end
end

function TaskGuideController.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
		local created, reason = TutorialPresentation.Create(playerGui, {
			NamePrefix = "TaskGuide",
			ShowPopup = false,
			ShowClickMask = false,
			ShowClickHand = true,
		})
		if not created then
			warn("任务解锁引导表现不可用：" .. tostring(reason))
			return
		end
		presentation = created

		local query, taskPresentation = getRemotes()
		if not query or not taskPresentation then
			warn("任务解锁引导 Remote 不存在")
			created.Destroy()
			presentation = nil
			return
		end
		queryRemote = query
		taskPresentation.OnClientEvent:Connect(function(snapshot)
			receiveSnapshot(snapshot)
		end)

		refreshState()
		local nextRefreshAt = os.clock() + 1
		while started and localPlayer.Parent do
			applySnapshot()
			if os.clock() >= nextRefreshAt then
				refreshState()
				nextRefreshAt = os.clock() + 1
			end
			task.wait(POLL_SECONDS)
		end

		created.Destroy()
		presentation = nil
	end)
end

return TaskGuideController
