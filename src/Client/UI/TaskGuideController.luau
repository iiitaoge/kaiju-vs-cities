--[[
	职责：当前区域任务的下一按钮可执行时，用 HUD.Guide 指向该按钮。
	输入：TaskPresentation 快照、当前玩家 Plot、ZoneCatalog 和 ButtonRequest 的 Ready 状态。
	输出：前置区域未满级时指向升级按钮，满级后指向目标区域解锁按钮；只显示小手箭头，
	不显示遮罩、聚焦高亮或世界 Beam；按钮不可执行时隐藏。
	内部算法：从 UnlockZone 任务解析目标 Zone；按 Current/Target 选择前置 Upgrade 或目标
	Unlock 按钮，并使用服务器 GetState 结果决定是否显示。
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
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local TaskPresentationProtocol = require(
	ReplicatedStorage.Shared.Task.TaskPresentationProtocol
)
local TaskProtocol = require(ReplicatedStorage.Shared.Task.TaskProtocol)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

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

local function getTaskZoneId(snapshot: TaskPresentationProtocol.Snapshot): string?
	if not snapshot.Visible
		or not snapshot.TaskId
		or snapshot.Current == nil
		or snapshot.Target == nil
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

local function resolveNextButton(
	snapshot: TaskPresentationProtocol.Snapshot
): (string?, string?)
	local zoneId = getTaskZoneId(snapshot)
	if not zoneId then
		return nil, nil
	end

	local definition = ZoneCatalog.Get(zoneId)
	local current = snapshot.Current
	local target = snapshot.Target
	if not definition or current == nil or target == nil then
		return nil, nil
	end
	if current < target then
		local prerequisiteZoneId = definition.UnlockPrerequisiteZoneId
		if not prerequisiteZoneId then
			return nil, nil
		end
		return prerequisiteZoneId .. "-Upgrade-Button", prerequisiteZoneId
	end
	return zoneId .. "-Unlock-Button", zoneId
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
	local buttonName, buttonZoneId = resolveNextButton(snapshot)
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
