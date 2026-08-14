--[[
	职责：当前区域任务对应的实体按钮可执行时，用 HUD.Guide 指向该按钮。
	输入：TaskPresentation 快照、任务要求、当前玩家 Plot 和 ButtonRequest 的 Ready 状态。
	输出：区域等级任务指向升级按钮，区域解锁任务指向解锁按钮；只显示小手箭头，
	不显示遮罩、聚焦高亮或世界 Beam；屏幕外目标把箭头夹在对应屏幕边缘。
	内部算法：从当前任务的唯一要求解析按钮合同，再用服务器 GetState 决定是否显示。
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
local TutorialController = require(script.Parent.Parent.Tutorial.TutorialController)
local TaskConfigs = require(ReplicatedStorage.Shared.Task.TaskConfigs)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local TaskPresentationProtocol = require(
	ReplicatedStorage.Shared.Task.TaskPresentationProtocol
)
local TaskProtocol = require(ReplicatedStorage.Shared.Task.TaskProtocol)

local TaskGuideController = {}

local POLL_SECONDS = 0.35
local BUTTON_STATE_POLL_SECONDS = 1
local localPlayer = Players.LocalPlayer
local started = false
local queryRemote: RemoteFunction? = nil
local buttonRequest: RemoteFunction? = nil
local presentation: TutorialPresentation.Handle? = nil
local pendingSnapshot: TaskPresentationProtocol.Snapshot? = nil
local currentTarget: BasePart? = nil
local checkedButtonName: string? = nil
local checkedButtonReady = false
local checkedButtonAt = 0

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

local function resolveTaskButton(
	snapshot: TaskPresentationProtocol.Snapshot
): (string?, string?)
	if not snapshot.Visible
		or not snapshot.TaskId
	then
		return nil, nil
	end

	local taskDefinition = TaskConfigs.Tasks[snapshot.TaskId]
	if not taskDefinition then
		return nil, nil
	end
	for _, requirement in taskDefinition.Requirements do
		local zoneId = requirement.Config.ZoneId
		if type(zoneId) ~= "string" or zoneId == "" then
			continue
		end
		if requirement.Kind == TaskProtocol.RequirementKinds.ReachRegionLevel then
			return zoneId .. "-Upgrade-Button", zoneId
		elseif requirement.Kind == TaskProtocol.RequirementKinds.UnlockZone then
			return zoneId .. "-Unlock-Button", zoneId
		end
	end
	return nil, nil
end

local function isButtonReady(buttonName: string): boolean
	local now = os.clock()
	if checkedButtonName == buttonName
		and now - checkedButtonAt < BUTTON_STATE_POLL_SECONDS
	then
		return checkedButtonReady
	end

	checkedButtonName = buttonName
	checkedButtonAt = now
	local remote = buttonRequest
	if not remote then
		checkedButtonReady = false
		return false
	end
	local succeeded, _, state = pcall(
		remote.InvokeServer,
		remote,
		buttonName,
		"GetState"
	)
	checkedButtonReady = succeeded and state == "Ready"
	return checkedButtonReady
end

local function resolveTarget(snapshot: TaskPresentationProtocol.Snapshot): BasePart?
	local buttonName, buttonZoneId = resolveTaskButton(snapshot)
	if not buttonName or not buttonZoneId then
		return nil
	end

	local plot = LocalPlayerPlotAccess.Find(localPlayer.UserId)
	local button = if plot
		then LocalPlotButtonAccess.FindInPlot(
			plot,
			buttonZoneId,
			buttonName
		)
		else nil
	if not button or not isButtonReady(buttonName) then
		return nil
	end
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
			WorldPart = nil,
			WorldPosition = target.Position,
			WorldBounds = nil,
			ScreenCenter = nil,
			ClampToViewport = true,
		})
	elseif currentTarget ~= nil then
		currentTarget = nil
		currentPresentation.Hide()
	end
end

local function receiveSnapshot(snapshot): boolean
	local valid, reason = TaskPresentationProtocol.Validate(snapshot)
	if not valid then
		warn("拒绝无效任务箭头引导快照：" .. tostring(reason))
		return false
	end
	local previousTaskId = pendingSnapshot and pendingSnapshot.TaskId
	pendingSnapshot = snapshot
	if previousTaskId ~= snapshot.TaskId then
		checkedButtonName = nil
		checkedButtonReady = false
		checkedButtonAt = 0
	end
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
		warn("任务箭头引导状态请求失败：" .. tostring(response))
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
		TutorialController.WaitUntilComplete()
		if not started or not localPlayer.Parent then
			return
		end
		local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
		local created, reason = TutorialPresentation.Create(playerGui, {
			NamePrefix = "TaskGuide",
			ShowPopup = false,
			ShowClickMask = false,
			ShowClickHand = true,
		})
		if not created then
			warn("任务箭头引导表现不可用：" .. tostring(reason))
			return
		end
		presentation = created

		local query, taskPresentation = getRemotes()
		if not query or not taskPresentation then
			warn("任务箭头引导 Remote 不存在")
			created.Destroy()
			presentation = nil
			return
		end
		local buttonRequestInstance = InstancePath.Find(
			"ReplicatedStorage/Remotes/ButtonRequest"
		)
		if not buttonRequestInstance or not buttonRequestInstance:IsA("RemoteFunction") then
			warn("任务箭头引导 ButtonRequest 不存在")
			created.Destroy()
			presentation = nil
			return
		end
		buttonRequest = buttonRequestInstance
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
