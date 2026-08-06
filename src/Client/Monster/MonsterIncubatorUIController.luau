--[[
	职责：把本地玩家最近的已建培养罐 MonsterUI 以近距离屏幕面板接到现有怪兽管理与攻击选择链。
	输入：本地玩家 M1-S1 至 M1-S4 的运行时培养罐、玩家位置、余额镜像和服务器管理快照。
	输出：安全区内固定显示的标题、现金升级价格、Start/升级按钮状态及点击请求。
	内部算法：在显示范围内选择水平距离最近的培养罐，将其 Panel 挂到独立 ScreenGui，组合管理状态机；怪兽回到 IdleAtSpawn 时重新打开。
	不负责：创建 UI、美术布局、扣款、升级模型、选择攻击目标或 Robux 购买。
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
local AttackSelectionHUDController = require(script.Parent.AttackSelectionHUDController)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local MoneyProtocol = require(ReplicatedStorage.Shared.Economy.MoneyProtocol)
local MonsterIncubatorUIPresentationConfig = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorUIPresentationConfig
)
local MonsterIncubatorUIPlacement = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorUIPlacement
)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)
local CompactNumberFormatter = require(
	ReplicatedStorage.Shared.UI.CompactNumberFormatter
)
local ResponsiveUIScale = require(ReplicatedStorage.Shared.UI.ResponsiveUIScale)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local LocalUIVisibilityGate = require(
	script.Parent.Parent.UI.LocalUIVisibilityGate
)
local AnalyticsIntentProtocol = require(
	ReplicatedStorage.Shared.Analytics.AnalyticsIntentProtocol
)

local MonsterIncubatorUIController = {}

local PLOT_WAIT_TIMEOUT = 20
local BUILD_RETRY_DELAY = 0.25
local BINDING_REFRESH_SECONDS = 0.1
local RESPONSIVE_SCALE_NAME = "ResponsiveUIScale"
local SCREEN_GUI_NAME = "MonsterManagementScreen"
local SCREEN_CONTAINER_NAME = "Container"
local started = false

local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
end

local function getOrCreateResponsiveScale(panel: Frame): UIScale
	local existing = panel:FindFirstChild(RESPONSIVE_SCALE_NAME)
	if existing and existing:IsA("UIScale") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local uiScale = Instance.new("UIScale")
	uiScale.Name = RESPONSIVE_SCALE_NAME
	uiScale.Parent = panel
	return uiScale
end

local function createScreenPresentation(playerGui: PlayerGui, panel: Frame): ScreenGui
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
	container.Name = SCREEN_CONTAINER_NAME
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = false
	container.AnchorPoint = MonsterIncubatorUIPresentationConfig.ScreenAnchorPoint
	container.Position = MonsterIncubatorUIPresentationConfig.ScreenPosition
	container.Size = UDim2.fromOffset(
		math.round(maximumCanvasSize.X),
		math.round(maximumCanvasSize.Y)
	)
	container.Parent = screenGui
	panel.Parent = container
	screenGui.Parent = playerGui
	return screenGui
end

function MonsterIncubatorUIController.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui")
		local plot = LocalMonsterBuildPresentationAccess.WaitForPlot(
			player.UserId,
			PLOT_WAIT_TIMEOUT
		)
		if not plot then
			warn("怪兽培养罐 UI：找不到本地玩家 Plot")
			return
		end

		local boundIncubator: Model? = nil
		local boundSpawnPointId: string? = nil
		local references: LocalMonsterIncubatorUIAccess.References? = nil
		local management = nil
		local currentMonster: Model? = nil
		local responsiveScale: UIScale? = nil
		local screenGui: ScreenGui? = nil
		local visibilityGate: LocalUIVisibilityGate.Handle? = nil
		local managementWantsVisible = false
		local isWithinProximity = false
		local lastViewportSize: Vector2? = nil
		local uiConnections: { RBXScriptConnection } = {}
		local monsterConnections: { RBXScriptConnection } = {}
		local retryToken = 0
		local refreshScheduled = false
		local lastBindingRefresh = 0
		local managementOpenReported = false

		local function disconnectAll(connections: { RBXScriptConnection })
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
		end

		local function applyVisibility()
			local gate = visibilityGate
			if gate then
				gate:SetDesiredVisible(managementWantsVisible and isWithinProximity)
			end
		end

		local function updateSpatialPresentation()
			local refs = references
			local uiScale = responsiveScale
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not refs or not uiScale or not root or not root:IsA("BasePart") then
				isWithinProximity = false
				applyVisibility()
				return
			end

			isWithinProximity = MonsterIncubatorUIPlacement.IsWithinHorizontalDistance(
				root.Position,
				refs.Glass.Position,
				MonsterIncubatorUIPresentationConfig.HorizontalActivationDistance
			)

			local camera = Workspace.CurrentCamera
			if camera then
				local viewportSize = camera.ViewportSize
				if lastViewportSize ~= viewportSize then
					lastViewportSize = viewportSize
					local scale = ResponsiveUIScale.Compute(
						viewportSize,
						UserInputService.TouchEnabled,
						MonsterIncubatorUIPresentationConfig.ResponsiveScale
					)
					uiScale.Scale = scale
						/ MonsterIncubatorUIPresentationConfig.ResponsiveScale.MaxScale
				end
			end
			applyVisibility()
		end

		local function render(state)
			local refs = references
			if not refs then
				return
			end
			local snapshot = state.Snapshot
			managementWantsVisible = state.Mode == "Managing"
				or state.Mode == "Upgrading"
				or state.Mode == "SelectingAttack"
			applyVisibility()
			if state.Mode == "Managing" and snapshot and not managementOpenReported
				and boundSpawnPointId
			then
				managementOpenReported = true
				AnalyticsIntentClient.Record(
					AnalyticsIntentProtocol.Intents.MonsterManagementOpened,
					boundSpawnPointId
				)
			elseif (state.Mode == "Closed" or state.Mode == "Error")
				and managementOpenReported
				and boundSpawnPointId
			then
				AnalyticsIntentClient.Record(
					AnalyticsIntentProtocol.Intents.MonsterManagementClosed,
					boundSpawnPointId,
					state.LastReason or state.Mode
				)
				managementOpenReported = false
			end
			refs.Robux.Visible = false
			refs.StartValue.Text = if state.Mode == "SelectingAttack" then "Select Target" else "Start"

			if snapshot then
				local definition = snapshot.MonsterKey and MonsterCatalog.Get(snapshot.MonsterKey)
				local displayName = if definition then definition.DisplayName else "Monster"
				refs.Title.Text = string.format("%s · Lv %d", displayName, snapshot.Level)
				refs.MoneyValue.Text = if snapshot.Upgrade.Reason == "MaxLevel"
					then "MAX"
					else CompactNumberFormatter.Format(snapshot.Upgrade.Cost)
			else
				refs.Title.Text = "Godzilla"
				refs.MoneyValue.Text = "..."
			end

			local canInteract = state.Mode == "Managing" and snapshot ~= nil
			setButtonEnabled(
				refs.StartButton,
				canInteract and snapshot.Attack.Allowed
			)
			setButtonEnabled(
				refs.MoneyButton,
				canInteract and snapshot.Upgrade.Allowed and snapshot.Upgrade.Affordable
			)

			retryToken += 1
			if state.Mode == "Error" and state.LastReason == "SpawnPointNotBuilt" then
				local ownToken = retryToken
				task.delay(BUILD_RETRY_DELAY, function()
					if ownToken == retryToken and management
						and boundIncubator and boundIncubator.Parent
						and management.GetState().Mode == "Error"
					then
						management.Retry()
					end
				end)
			end
		end

		local function unbindIncubator()
			retryToken += 1
			disconnectAll(uiConnections)
			managementWantsVisible = false
			isWithinProximity = false
			lastViewportSize = nil
			if management then
				management.Close()
			end
			if visibilityGate then
				visibilityGate:Destroy()
				visibilityGate = nil
			end
			if references then
				local refs = references
				refs.Gui.Enabled = false
				if refs.Gui.Parent and refs.Attachment.Parent then
					refs.Panel.Parent = refs.Gui
				elseif refs.Panel.Parent then
					refs.Panel:Destroy()
				end
			end
			if screenGui then
				screenGui:Destroy()
			end
			management = nil
			responsiveScale = nil
			screenGui = nil
			references = nil
			boundIncubator = nil
			boundSpawnPointId = nil
			managementOpenReported = false
		end

		local function bindIncubator(
			spawnPointId: string,
			incubator: Model,
			resolved: LocalMonsterIncubatorUIAccess.References
		)
			if boundSpawnPointId == spawnPointId and boundIncubator == incubator then
				return
			end
			unbindIncubator()
			boundSpawnPointId = spawnPointId
			boundIncubator = incubator
			references = resolved
			managementWantsVisible = false
			isWithinProximity = false
			lastViewportSize = nil
			resolved.Gui.Enabled = false
			responsiveScale = getOrCreateResponsiveScale(resolved.Panel)
			resolved.Robux.Visible = false
			screenGui = createScreenPresentation(playerGui, resolved.Panel)
			visibilityGate = LocalUIVisibilityGate.Create(
				UIModeVisibilityRules.Channels.Gameplay,
				function(visible)
					local layer = screenGui
					if layer then
						layer.Enabled = visible
					end
				end,
				false
			)
			updateSpatialPresentation()
			management = MonsterManagementCoordinator.Create({
				Render = render,
				OpenAttackSelection = AttackSelectionHUDController.Open,
			})
			local session = management
			table.insert(uiConnections, resolved.StartButton.Activated:Connect(function()
				AnalyticsIntentClient.Record(
					AnalyticsIntentProtocol.Intents.AttackStartClicked,
					spawnPointId
				)
				session.ChooseAttack()
			end))
			table.insert(uiConnections, resolved.MoneyButton.Activated:Connect(function()
				AnalyticsIntentClient.Record(
					AnalyticsIntentProtocol.Intents.MonsterUpgradeClicked,
					spawnPointId
				)
				session.ChooseUpgrade()
			end))
			session.Open(spawnPointId)
		end

		local function handleMonsterState()
			if not currentMonster or not management then
				return
			end
			local monsterState = currentMonster:GetAttribute("MonsterState")
			local mode = management.GetState().Mode
			if monsterState == "IdleAtSpawn" and mode == "Closed" and boundSpawnPointId then
				management.Open(boundSpawnPointId)
			elseif monsterState ~= "IdleAtSpawn"
				and (mode == "Managing" or mode == "Upgrading")
			then
				management.Close()
			end
		end

		local function bindMonster(monster: Model?)
			if currentMonster == monster then
				return
			end
			disconnectAll(monsterConnections)
			currentMonster = monster
			if not monster then
				return
			end
			table.insert(monsterConnections, monster:GetAttributeChangedSignal("MonsterState"):Connect(
				handleMonsterState
			))
			table.insert(monsterConnections, monster.AncestryChanged:Connect(function()
				if not monster.Parent then
					task.defer(function()
						local activeSpawnPointId = boundSpawnPointId
						bindMonster(if activeSpawnPointId
							then LocalMonsterBuildPresentationAccess.FindMonsterForSpawnPoint(
								plot,
								activeSpawnPointId,
								player.UserId
							)
							else nil)
					end)
				end
			end))
			handleMonsterState()
		end

		local function refreshRuntimeBindings()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local nearestSpawnPointId: string? = nil
			local nearestIncubator: Model? = nil
			local nearestReferences: LocalMonsterIncubatorUIAccess.References? = nil
			local nearestDistance = math.huge

			if root and root:IsA("BasePart") then
				for _, definition in MonsterSpawnPointCatalog.GetAll() do
					local incubator = LocalMonsterBuildPresentationAccess.FindIncubator(
						plot,
						definition.SpawnPointId,
						player.UserId
					)
					local resolved = if incubator == boundIncubator
						and definition.SpawnPointId == boundSpawnPointId
						then references
						elseif incubator
						then LocalMonsterIncubatorUIAccess.Resolve(incubator)
						else nil
					if incubator and resolved then
						local distance = MonsterIncubatorUIPlacement.HorizontalDistance(
							root.Position,
							resolved.Glass.Position
						)
						if distance <= MonsterIncubatorUIPresentationConfig.HorizontalActivationDistance
							and distance < nearestDistance
						then
							nearestSpawnPointId = definition.SpawnPointId
							nearestIncubator = incubator
							nearestReferences = resolved
							nearestDistance = distance
						end
					end
				end
			end

			if nearestSpawnPointId and nearestIncubator and nearestReferences then
				bindIncubator(nearestSpawnPointId, nearestIncubator, nearestReferences)
			elseif boundIncubator then
				unbindIncubator()
			end

			local activeSpawnPointId = boundSpawnPointId
			local monster = if activeSpawnPointId
				then LocalMonsterBuildPresentationAccess.FindMonsterForSpawnPoint(
					plot,
					activeSpawnPointId,
					player.UserId
				)
				else nil
			bindMonster(monster)
			if monster and management then
				local state = management.GetState()
				local runtimeMonsterKey = monster:GetAttribute("MonsterKey")
				if state.Mode == "Managing" and state.Snapshot
					and state.Snapshot.MonsterKey ~= runtimeMonsterKey
				then
					management.Retry()
				end
			end
		end

		local function scheduleRefresh()
			if refreshScheduled then
				return
			end
			refreshScheduled = true
			task.defer(function()
				refreshScheduled = false
				refreshRuntimeBindings()
			end)
		end

		plot.DescendantAdded:Connect(scheduleRefresh)
		plot.DescendantRemoving:Connect(scheduleRefresh)
		player:GetAttributeChangedSignal(MoneyProtocol.BalanceAttributeName):Connect(function()
			local balance = player:GetAttribute(MoneyProtocol.BalanceAttributeName)
			if management and type(balance) == "number" then
				management.UpdateBalance(balance)
			end
		end)
		RunService.RenderStepped:Connect(function()
			local now = os.clock()
			if now - lastBindingRefresh >= BINDING_REFRESH_SECONDS then
				lastBindingRefresh = now
				refreshRuntimeBindings()
			end
			updateSpatialPresentation()
		end)
		refreshRuntimeBindings()
	end)
end

return MonsterIncubatorUIController
