--[[
	职责：把服务器任务卡片快照渲染到现有 PlayerGui.HUD.LeftTask。
	输入：TaskPresentationRequest 初始快照和 TaskPresentation RemoteEvent 更新。
	输出：LeftTask.Task.Panel 的任务文本、进度条、进度文本、奖励图标和奖励数量。
	内部算法：解析固定 UI 合同 → 校验快照 → 按 Current/Target 设置 Bar 宽度 →
	调用 CurrencyIconRenderer 按 RewardKind 切换图标；没有活动任务时隐藏整张卡片。
	不负责：任务配置、进度计算、奖励发放、存档或创建 UI Instance。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CompactNumberFormatter = require(
	ReplicatedStorage.Shared.UI.CompactNumberFormatter
)
local TaskPresentationProtocol = require(
	ReplicatedStorage.Shared.Task.TaskPresentationProtocol
)
local CurrencyIconRenderer = require(script.Parent.CurrencyIconRenderer)
local LocalCombatVisibilityService = require(
	script.Parent.LocalCombatVisibilityService
)
local LocalUIModeService = require(script.Parent.LocalUIModeService)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)

local TaskUIController = {}

type ImageTarget = ImageLabel | ImageButton

type References = {
	Root: GuiObject,
	Text: TextLabel,
	Bar: Frame,
	ProgressValue: TextLabel,
	RewardIcon: ImageTarget,
	RewardValue: TextLabel,
}

type ServerResponse = {
	Succeeded: boolean,
	Reason: string?,
	Snapshot: TaskPresentationProtocol.Snapshot?,
}

local localPlayer = Players.LocalPlayer
local references: References? = nil
local pendingSnapshot: TaskPresentationProtocol.Snapshot? = nil
local queryRemote: RemoteFunction? = nil
local started = false
local desiredVisible = false

local function childOf(parent: Instance?, name: string): Instance?
	return parent and parent:FindFirstChild(name)
end

local function resolveGuiObject(parent: Instance?, name: string): GuiObject?
	local child = childOf(parent, name)
	if child and child:IsA("GuiObject") then
		return child
	end
	return nil
end

local function resolveTextLabel(parent: Instance?, name: string): TextLabel?
	local child = childOf(parent, name)
	if child and child:IsA("TextLabel") then
		return child
	end
	return nil
end

local function resolveImageTarget(parent: Instance?, name: string): ImageTarget?
	local child = childOf(parent, name)
	if child and (child:IsA("ImageLabel") or child:IsA("ImageButton")) then
		return child :: ImageTarget
	end
	return nil
end

local function resolve(playerGui: PlayerGui): (References?, string?)
	local hud = playerGui:FindFirstChild("HUD")
	local root = resolveGuiObject(hud, "LeftTask")
	local taskFrame = resolveGuiObject(root, "Task")
	local panel = resolveGuiObject(taskFrame, "Panel")
	local text = resolveTextLabel(panel, "Texter")
	local progressBar = resolveGuiObject(panel, "ProgressBar")
	local bar = if progressBar then resolveGuiObject(progressBar, "Bar") else nil
	local progressValue = if progressBar
		then resolveTextLabel(progressBar, "Val")
		else nil
	local reward = resolveGuiObject(panel, "Money")
	local rewardIcon = resolveImageTarget(reward, "Icon")
	local rewardValue = resolveTextLabel(reward, "Val")

	if not hud or not hud:IsA("ScreenGui") then
		return nil, "HUDUnavailable"
	end
	if not root then
		return nil, "LeftTaskUnavailable"
	end
	if not taskFrame then
		return nil, "TaskUnavailable"
	end
	if not panel then
		return nil, "TaskPanelUnavailable"
	end
	if not text then
		return nil, "TaskTextUnavailable"
	end
	if not progressBar or not bar or not progressValue then
		return nil, "TaskProgressUnavailable"
	end
	if not reward or not rewardIcon or not rewardValue then
		return nil, "TaskRewardUnavailable"
	end

	return {
		Root = root,
		Text = text,
		Bar = bar :: Frame,
		ProgressValue = progressValue,
		RewardIcon = rewardIcon,
		RewardValue = rewardValue,
	}, nil
end

local function invoke(): ServerResponse?
	local remote = queryRemote
	if not remote then
		return nil
	end

	local succeeded, response = pcall(function()
		return remote:InvokeServer(TaskPresentationProtocol.RequestKinds.GetState)
	end)
	if not succeeded or type(response) ~= "table" then
		warn("任务卡片状态请求失败：" .. tostring(response))
		return nil
	end
	return response :: ServerResponse
end

local function applyVisibility()
	local current = references
	if not current then
		return
	end
	current.Root.Visible = desiredVisible
		and LocalUIModeService.IsAllowed(UIModeVisibilityRules.Channels.Gameplay)
		and not LocalCombatVisibilityService.IsActive()
end

local function render(snapshot: TaskPresentationProtocol.Snapshot)
	local current = references
	if not current then
		pendingSnapshot = snapshot
		return
	end

	if not snapshot.Visible then
		desiredVisible = false
		current.Root.Visible = false
		return
	end

	local currentValue = assert(snapshot.Current)
	local targetValue = assert(snapshot.Target)
	local ratio = math.clamp(currentValue / targetValue, 0, 1)
	desiredVisible = true
	current.Text.Text = assert(snapshot.Text)
	current.ProgressValue.Text = string.format(
		"%s/%s",
		CompactNumberFormatter.Format(currentValue),
		CompactNumberFormatter.Format(targetValue)
	)
	current.Bar.Size = UDim2.new(
		ratio,
		0,
		current.Bar.Size.Y.Scale,
		current.Bar.Size.Y.Offset
	)
	current.RewardValue.Text = CompactNumberFormatter.Format(assert(snapshot.RewardAmount))
	CurrencyIconRenderer.Apply(current.RewardIcon, assert(snapshot.RewardKind))
	applyVisibility()
end

local function refreshState()
	local response = invoke()
	if not response then
		return
	end
	if response.Snapshot then
		local valid, reason = TaskPresentationProtocol.Validate(response.Snapshot)
		if not valid then
			warn("拒绝无效任务卡片快照：" .. tostring(reason))
			return
		end
		render(response.Snapshot)
	end
	if not response.Succeeded and response.Reason == "PlayerDataNotReady" then
		task.delay(1, function()
			if started then
				refreshState()
			end
		end)
	end
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
	local presentation = remotes:WaitForChild(
		TaskPresentationProtocol.RemoteName,
		10
	)
	if not query or not query:IsA("RemoteFunction") then
		return nil, nil
	end
	if not presentation or not presentation:IsA("RemoteEvent") then
		return nil, nil
	end
	return query, presentation
end

function TaskUIController.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		local query, presentation = getRemotes()
		if not query or not presentation then
			warn("任务卡片 Remote 不存在")
			return
		end
		queryRemote = query
		presentation.OnClientEvent:Connect(function(snapshot)
			local valid, reason = TaskPresentationProtocol.Validate(snapshot)
			if not valid then
				warn("拒绝无效任务卡片推送：" .. tostring(reason))
				return
			end
			render(snapshot)
		end)

		local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
		local deadline = os.clock() + 10
		while started and playerGui.Parent and os.clock() < deadline do
			local resolved = resolve(playerGui)
			if resolved then
				references = resolved
				desiredVisible = false
				resolved.Root.Visible = false
				LocalUIModeService.Observe(applyVisibility)
				LocalCombatVisibilityService.Observe(applyVisibility)
				local queued = pendingSnapshot
				pendingSnapshot = nil
				if queued then
					render(queued)
				end
				refreshState()
				return
			end
			task.wait()
		end
		warn("任务卡片 UI 路径无效：HUD.LeftTask")
	end)
end

return TaskUIController
