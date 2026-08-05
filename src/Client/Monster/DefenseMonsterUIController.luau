--[[
	职责：靠近本地玩家的防守怪兽时打开与培养罐一致的升级面板。
	输入：己方运行时防守怪兽、玩家位置和管理服务器快照。
	输出：范围内最近怪兽的等级/价格与现金升级入口；离开后关闭面板，并隐藏 Start/Robux。
	内部算法：复用 PetriDish-3 UI，周期扫描 MonsterRole=Defense 的己方空闲模型并选择 20 studs 内最近目标。
	不负责：生成怪兽、攻击选择、价格、扣款、升级或战斗。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AnalyticsIntentClient = require(script.Parent.Parent.Analytics.AnalyticsIntentClient)
local LocalMonsterBuildPresentationAccess = require(script.Parent.LocalMonsterBuildPresentationAccess)
local LocalMonsterIncubatorUIAccess = require(script.Parent.LocalMonsterIncubatorUIAccess)
local MonsterManagementCoordinator = require(script.Parent.MonsterManagementCoordinator)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local MonsterIncubatorUIPresentationConfig = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorUIPresentationConfig
)
local MonsterIncubatorUIPlacement = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorUIPlacement
)
local ResponsiveUIScale = require(ReplicatedStorage.Shared.UI.ResponsiveUIScale)
local AnalyticsIntentProtocol = require(
	ReplicatedStorage.Shared.Analytics.AnalyticsIntentProtocol
)

local DefenseMonsterUIController = {}

local SCREEN_GUI_NAME = "DefenseMonsterManagementScreen"
local BINDING_REFRESH_SECONDS = 0.1
local PLOT_WAIT_TIMEOUT = 20
local started = false

local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
end

local function createPresentation(playerGui: PlayerGui)
	local root = ReplicatedStorage:FindFirstChild("MonsterIncubators")
	local template = root and root:FindFirstChild("PetriDish-3")
	if not template or not template:IsA("Model") then
		return nil, nil, "MissingMonsterUITemplate"
	end
	local clone = template:Clone()
	local refs, reason = LocalMonsterIncubatorUIAccess.Resolve(clone)
	if not refs then
		clone:Destroy()
		return nil, nil, reason
	end
	local existing = playerGui:FindFirstChild(SCREEN_GUI_NAME)
	if existing then
		existing:Destroy()
	end
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = SCREEN_GUI_NAME
	screenGui.Enabled = false
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screenGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension
	screenGui.ClipToDeviceSafeArea = true
	screenGui.DisplayOrder = MonsterIncubatorUIPresentationConfig.DisplayOrder
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local maximumCanvasSize = MonsterIncubatorUIPresentationConfig.BaseCanvasSize
		* MonsterIncubatorUIPresentationConfig.ResponsiveScale.MaxScale
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.AnchorPoint = MonsterIncubatorUIPresentationConfig.ScreenAnchorPoint
	container.Position = MonsterIncubatorUIPresentationConfig.ScreenPosition
	container.Size = UDim2.fromOffset(maximumCanvasSize.X, maximumCanvasSize.Y)
	container.Parent = screenGui
	refs.Panel.Parent = container
	screenGui.Parent = playerGui
	clone:Destroy()

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "ResponsiveUIScale"
	uiScale.Parent = refs.Panel
	local startFrame = refs.StartButton.Parent
	if startFrame and startFrame:IsA("GuiObject") then
		startFrame.Visible = false
	end
	refs.Robux.Visible = false
	return refs, {
		Gui = screenGui,
		Scale = uiScale,
	}, nil
end

function DefenseMonsterUIController.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui")
		local plot = LocalMonsterBuildPresentationAccess.WaitForPlot(player.UserId, PLOT_WAIT_TIMEOUT)
		if not plot then
			warn("防守怪兽 UI：找不到本地玩家 Plot")
			return
		end
		local refs, presentation, presentationReason = createPresentation(playerGui)
		if not refs or not presentation then
			warn("防守怪兽 UI：无法复用培养罐面板：", presentationReason)
			return
		end

		local selectedSpawnPointId: string? = nil
		local selectedModel: Model? = nil
		local wantsVisible = false
		local lastViewportSize: Vector2? = nil
		local management
		local managementOpenReported = false

		local function render(state)
			local snapshot = state.Snapshot
			wantsVisible = state.Mode == "Managing" or state.Mode == "Upgrading"
			if state.Mode == "Managing" and snapshot and not managementOpenReported
				and selectedSpawnPointId
			then
				managementOpenReported = true
				AnalyticsIntentClient.Record(
					AnalyticsIntentProtocol.Intents.MonsterManagementOpened,
					selectedSpawnPointId
				)
			elseif (state.Mode == "Closed" or state.Mode == "Error")
				and managementOpenReported
				and selectedSpawnPointId
			then
				AnalyticsIntentClient.Record(
					AnalyticsIntentProtocol.Intents.MonsterManagementClosed,
					selectedSpawnPointId,
					state.LastReason or state.Mode
				)
				managementOpenReported = false
			end
			refs.Robux.Visible = false
			if snapshot then
				local definition = snapshot.MonsterKey and MonsterCatalog.Get(snapshot.MonsterKey)
				refs.Title.Text = string.format(
					"%s · Lv %d",
					if definition then definition.DisplayName else "Godzilla",
					snapshot.Level
				)
				refs.MoneyValue.Text = if snapshot.Upgrade.Reason == "MaxLevel"
					then "MAX"
					else tostring(snapshot.Upgrade.Cost)
			else
				refs.Title.Text = "Godzilla"
				refs.MoneyValue.Text = "..."
			end
			local canInteract = state.Mode == "Managing" and snapshot ~= nil
			setButtonEnabled(
				refs.MoneyButton,
				canInteract and snapshot.Upgrade.Allowed and snapshot.Upgrade.Affordable
			)
		end

		management = MonsterManagementCoordinator.Create({ Render = render })
		refs.MoneyButton.Activated:Connect(function()
			if selectedSpawnPointId then
				AnalyticsIntentClient.Record(
					AnalyticsIntentProtocol.Intents.MonsterUpgradeClicked,
					selectedSpawnPointId
				)
			end
			management.ChooseUpgrade()
		end)

		local function isOwnDefenseMonster(model: Instance): boolean
			return model:IsA("Model")
				and model:GetAttribute("MonsterOwnerUserId") == player.UserId
				and model:GetAttribute("MonsterRole") == "Defense"
		end

		local function getRuntimeRoot(): Folder?
			local runtime = plot:FindFirstChild("Runtime")
			local root = runtime and runtime:FindFirstChild("Monsters")
			return if root and root:IsA("Folder") then root else nil
		end

		local function findNearestDefenseMonster(
			rootPosition: Vector3
		): (Model?, string?)
			local runtimeRoot = getRuntimeRoot()
			if not runtimeRoot then
				return nil, nil
			end

			local nearestModel: Model? = nil
			local nearestSpawnPointId: string? = nil
			local nearestDistance = math.huge
			for _, child in runtimeRoot:GetChildren() do
				if not isOwnDefenseMonster(child)
					or child:GetAttribute("MonsterState") ~= "IdleAtSpawn"
				then
					continue
				end
				local spawnPointId = child:GetAttribute("MonsterSpawnPointId")
				if type(spawnPointId) ~= "string" then
					continue
				end
				local distance = MonsterIncubatorUIPlacement.HorizontalDistance(
					rootPosition,
					child:GetPivot().Position
				)
				if distance <= MonsterIncubatorUIPresentationConfig.HorizontalActivationDistance
					and distance < nearestDistance
				then
					nearestModel = child
					nearestSpawnPointId = spawnPointId
					nearestDistance = distance
				end
			end
			return nearestModel, nearestSpawnPointId
		end

		local function selectDefenseMonster(model: Model?, spawnPointId: string?)
			if model == selectedModel and spawnPointId == selectedSpawnPointId then
				if model and spawnPointId then
					local state = management.GetState()
					if state.Mode == "Closed" then
						management.Open(spawnPointId)
					elseif state.Mode == "Managing" and state.Snapshot
						and state.Snapshot.MonsterKey ~= model:GetAttribute("MonsterKey")
					then
						management.Retry()
					end
				end
				return
			end

			if selectedSpawnPointId then
				management.Close()
			end
			selectedModel = model
			selectedSpawnPointId = spawnPointId
			if spawnPointId then
				management.Open(spawnPointId)
			end
		end

		local function refreshSelection()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				selectDefenseMonster(nil, nil)
				return
			end
			local model, spawnPointId = findNearestDefenseMonster(root.Position)
			selectDefenseMonster(model, spawnPointId)
		end

		local lastRefresh = 0
		RunService.RenderStepped:Connect(function()
			local now = os.clock()
			if now - lastRefresh >= BINDING_REFRESH_SECONDS then
				lastRefresh = now
				refreshSelection()
			end
			presentation.Gui.Enabled = wantsVisible
				and selectedModel ~= nil
				and selectedModel.Parent ~= nil

			local camera = Workspace.CurrentCamera
			if camera and lastViewportSize ~= camera.ViewportSize then
				lastViewportSize = camera.ViewportSize
				presentation.Scale.Scale = ResponsiveUIScale.Compute(
					camera.ViewportSize,
					UserInputService.TouchEnabled,
					MonsterIncubatorUIPresentationConfig.ResponsiveScale
				) / MonsterIncubatorUIPresentationConfig.ResponsiveScale.MaxScale
			end
		end)
		refreshSelection()
	end)
end

return DefenseMonsterUIController
