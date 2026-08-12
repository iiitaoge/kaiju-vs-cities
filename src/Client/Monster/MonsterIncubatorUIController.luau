--[[
	职责：把本地玩家最近的进攻培养罐或防守怪兽接到 HUD.Panel 管理面板。
	输入：本地玩家运行时培养罐/防守怪兽、玩家位置、余额镜像和服务器管理快照。
	输出：HUD.Panel 固定显示标题、金币逐级升级价格、钻石满级升级价格、攻击/升级按钮状态及点击请求。
	内部算法：在显示范围内选择水平距离最近的可管理目标；进攻培养罐显示攻击和升级，防守怪兽只显示升级；两者共用一个管理会话。
	不负责：创建 UI、美术布局、扣款、升级模型、选择攻击目标或 Robux 购买。
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnalyticsIntentClient = require(script.Parent.Parent.Analytics.AnalyticsIntentClient)
local LocalMonsterBuildPresentationAccess = require(script.Parent.LocalMonsterBuildPresentationAccess)
local LocalMonsterIncubatorUIAccess = require(script.Parent.LocalMonsterIncubatorUIAccess)
local LocalMonsterManagementPanelAccess = require(
	script.Parent.LocalMonsterManagementPanelAccess
)
local MonsterManagementCoordinator = require(script.Parent.MonsterManagementCoordinator)
local AttackSelectionHUDController = require(script.Parent.AttackSelectionHUDController)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local PaidProductConfigs = require(ReplicatedStorage.Shared.Monetization.PaidProductConfigs)
local DiamondProtocol = require(ReplicatedStorage.Shared.Economy.DiamondProtocol)
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
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local LocalUIVisibilityGate = require(
	script.Parent.Parent.UI.LocalUIVisibilityGate
)
local LocalGuiButtonState = require(
	script.Parent.Parent.UI.LocalGuiButtonState
)
local TipBlackController = require(script.Parent.Parent.UI.TipBlackController)
local SoundController = require(script.Parent.Parent.Sound.SoundController)
local PaidPurchaseRemoteClient = require(
	script.Parent.Parent.Monetization.PaidPurchaseRemoteClient
)
local PaidPurchaseProtocol = require(ReplicatedStorage.Shared.Monetization.PaidPurchaseProtocol)
local AnalyticsIntentProtocol = require(
	ReplicatedStorage.Shared.Analytics.AnalyticsIntentProtocol
)

local MonsterIncubatorUIController = {}

-- Studio 原始 Robux 图标是写在 Val.Text 里的私有字符，不是独立 ImageLabel。
local ROBUX_ICON = utf8.char(0xE002)

local PLOT_WAIT_TIMEOUT = 20
local BUILD_RETRY_DELAY = 0.25
local BINDING_REFRESH_SECONDS = 0.1
local started = false

type TargetKind = "Attack" | "Defense"

type TargetCandidate = {
	Kind: TargetKind,
	SpawnPointId: string,
	Incubator: Model?,
	References: LocalMonsterIncubatorUIAccess.WorldReferences?,
	DefenseMonster: Model?,
	Position: Vector3,
}

local function setButtonEnabled(button: TextButton, enabled: boolean)
	LocalGuiButtonState.SetEnabled(button, enabled)
end

local function getRobuxButton(panel: Frame): TextButton?
	local button = panel:FindFirstChild("Button")
	return if button and button:IsA("TextButton") then button else nil
end

local function getRobuxValue(button: TextButton): TextLabel?
	local value = button:FindFirstChild("Val", true)
	return if value and value:IsA("TextLabel") then value else nil
end

function MonsterIncubatorUIController.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui")
		local panelReferences, panelReason = LocalMonsterManagementPanelAccess.Wait(
			playerGui
		)
		if not panelReferences then
			warn("怪兽管理 HUD.Panel 初始化失败：" .. tostring(panelReason))
			return
		end
		panelReferences.Panel.Visible = false
		panelReferences.Robux.Visible = false
		local robuxButton = getRobuxButton(panelReferences.Robux)
		local robuxValue = if robuxButton then getRobuxValue(robuxButton) else nil
		if robuxValue then
			robuxValue.Text = if PaidProductConfigs.MonsterUpgradeToMaxProductId > 0
				then ROBUX_ICON .. tostring(PaidProductConfigs.MonsterUpgradeToMaxPriceInRobux)
				else "Soon"
		end
		panelReferences.DiamondTip.Text = "Max Level"
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
		local boundTargetKind: TargetKind? = nil
		local boundDefenseMonster: Model? = nil
		local boundAnchorPosition: Vector3? = nil
		local references: LocalMonsterIncubatorUIAccess.WorldReferences? = nil
		local management = nil
		local currentMonster: Model? = nil
		local visibilityGate: LocalUIVisibilityGate.Handle? = nil
		local managementWantsVisible = false
		local isWithinProximity = false
		local uiConnections: { RBXScriptConnection } = {}
		local monsterConnections: { RBXScriptConnection } = {}
		local retryToken = 0
		local refreshScheduled = false
		local lastBindingRefresh = 0
		local managementOpenReported = false
		local robuxPromptBusy = false
		local robuxPromptProductId: number? = nil
		local robuxPromptSpawnPointId: string? = nil

		local function disconnectAll(connections: { RBXScriptConnection })
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
		end

		local function clearRobuxPromptState()
			robuxPromptBusy = false
			robuxPromptProductId = nil
			robuxPromptSpawnPointId = nil
		end

		local function cancelRobuxPrompt()
			local spawnPointId = robuxPromptSpawnPointId
			local productId = robuxPromptProductId
			if not spawnPointId or not productId then
				clearRobuxPromptState()
				return
			end
			robuxPromptProductId = nil
			robuxPromptSpawnPointId = nil
			task.spawn(function()
				local cancelled = PaidPurchaseRemoteClient.CancelMonsterUpgrade(
					spawnPointId,
					productId
				)
				if not cancelled.Succeeded then
					warn("取消付费怪兽意图失败：" .. tostring(cancelled.Reason))
				end
				robuxPromptBusy = false
				if management then
					management.Retry()
				end
			end)
		end

		local function applyVisibility()
			local gate = visibilityGate
			if gate then
				gate:SetDesiredVisible(managementWantsVisible and isWithinProximity)
			end
		end

		local function getBoundTargetPosition(): Vector3?
			if references then
				return references.Glass.Position
			end
			if boundDefenseMonster and boundDefenseMonster.Parent then
				return boundDefenseMonster:GetPivot().Position
			end
			return boundAnchorPosition
		end

		local function updateSpatialPresentation()
			local targetPosition = getBoundTargetPosition()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not targetPosition or not root or not root:IsA("BasePart") then
				isWithinProximity = false
				applyVisibility()
				return
			end

			isWithinProximity = MonsterIncubatorUIPlacement.IsWithinHorizontalDistance(
				root.Position,
				targetPosition,
				MonsterIncubatorUIPresentationConfig.HorizontalActivationDistance
			)
			applyVisibility()
		end

		local function render(state)
			local refs = panelReferences
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
			local startFrame = refs.StartButton.Parent
			if startFrame and startFrame:IsA("GuiObject") then
				startFrame.Visible = boundTargetKind == "Attack"
			end
			refs.StartValue.Text = if state.Mode == "SelectingAttack" then "Select Target" else "Start"

			if snapshot then
				local definition = snapshot.MonsterKey and MonsterCatalog.Get(snapshot.MonsterKey)
				local displayName = if definition then definition.DisplayName else "Monster"
				refs.Title.Text = string.format("%s · Lv %d", displayName, snapshot.Level)
				refs.MoneyValue.Text = if snapshot.Upgrade.Reason == "MaxLevel"
					then "Max Level"
					elseif snapshot.Upgrade.Reason == "RebirthRequired"
					then "Rebirth"
					else CompactNumberFormatter.Format(snapshot.Upgrade.Cost)
				refs.DiamondValue.Text = if snapshot.DiamondUpgrade.Reason == "MaxLevel"
					then "Max Level"
					elseif snapshot.DiamondUpgrade.Reason == "RebirthRequired"
					then "Rebirth"
					else CompactNumberFormatter.Format(snapshot.DiamondUpgrade.Cost)
				refs.DiamondTip.Text = if snapshot.DiamondUpgrade.Reason == "RebirthRequired"
					then "Requires Rebirth"
					else "Max Level"
			else
				refs.Title.Text = "Godzilla"
				refs.MoneyValue.Text = "..."
				refs.DiamondValue.Text = "..."
				refs.DiamondTip.Text = "Max Level"
			end

			local canInteract = state.Mode == "Managing" and snapshot ~= nil
			local paidUpgrade = snapshot and snapshot.RobuxUpgrade
			local hasRobuxProduct = type(paidUpgrade) == "table"
				and type(paidUpgrade.ProductId) == "number"
				and paidUpgrade.ProductId > 0
				and paidUpgrade.Allowed == true
			local showRobuxSlot = canInteract and robuxButton ~= nil
			if showRobuxSlot then
				refs.Robux.Visible = true
				if robuxValue then
					robuxValue.Text = if paidUpgrade.Reason == "RebirthRequired"
						then "Rebirth"
						elseif paidUpgrade.Reason == "MaxLevel"
						then "Max"
						elseif hasRobuxProduct
						then ROBUX_ICON .. tostring(PaidProductConfigs.MonsterUpgradeToMaxPriceInRobux)
						else "Soon"
				end
			end
			setButtonEnabled(
				refs.StartButton,
				boundTargetKind == "Attack"
					and canInteract
					and snapshot.Attack.Allowed
			)
			setButtonEnabled(
				refs.MoneyButton,
				canInteract and snapshot.Upgrade.Allowed
			)
			setButtonEnabled(
				refs.DiamondButton,
				canInteract and snapshot.DiamondUpgrade.Allowed
			)
			if robuxButton then
				setButtonEnabled(robuxButton, canInteract and hasRobuxProduct and not robuxPromptBusy)
			end

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
			if management then
				management.Close()
			end
			if visibilityGate then
				visibilityGate:Destroy()
				visibilityGate = nil
			end
			if references then
				local refs = references
				if refs.Gui then
					refs.Gui.Enabled = false
				end
			end
			panelReferences.Panel.Visible = false
			local startFrame = panelReferences.StartButton.Parent
			if startFrame and startFrame:IsA("GuiObject") then
				startFrame.Visible = false
			end
			management = nil
			references = nil
			boundIncubator = nil
			boundSpawnPointId = nil
			boundTargetKind = nil
			boundDefenseMonster = nil
			boundAnchorPosition = nil
			managementOpenReported = false
		end

		local function bindTarget(
			spawnPointId: string,
			targetKind: TargetKind,
			incubator: Model?,
			resolved: LocalMonsterIncubatorUIAccess.WorldReferences?,
			defenseMonster: Model?,
			anchorPosition: Vector3
		)
			if boundSpawnPointId == spawnPointId
				and boundTargetKind == targetKind
				and boundIncubator == incubator
				and boundDefenseMonster == defenseMonster
			then
				return
			end
			unbindIncubator()
			boundSpawnPointId = spawnPointId
			boundTargetKind = targetKind
			boundIncubator = incubator
			boundDefenseMonster = defenseMonster
			boundAnchorPosition = anchorPosition
			references = resolved
			managementWantsVisible = false
			isWithinProximity = false
			if resolved and resolved.Gui then
				resolved.Gui.Enabled = false
			end
			panelReferences.Panel.Visible = false
			panelReferences.Robux.Visible = false
			visibilityGate = LocalUIVisibilityGate.Create(
				UIModeVisibilityRules.Channels.Gameplay,
				function(visible)
					panelReferences.Panel.Visible = visible
				end,
				false
			)
			updateSpatialPresentation()
			management = MonsterManagementCoordinator.Create({
				Render = render,
				OpenAttackSelection = AttackSelectionHUDController.Open,
				OnInsufficientMoney = TipBlackController.ShowInsufficientMoney,
				OnInsufficientDiamonds = TipBlackController.ShowInsufficientDiamonds,
				OnUpgradeResult = function(succeeded, reason)
					if succeeded then
						SoundController.Play("Yes")
					elseif reason ~= "RequestFailed"
						and reason ~= "InvalidServerResponse"
						and reason ~= "PlayerDataNotReady"
					then
						SoundController.Play("No")
					end
				end,
			})
			local session = management
			table.insert(uiConnections, panelReferences.StartButton.Activated:Connect(function()
				if targetKind ~= "Attack" then
					return
				end
				AnalyticsIntentClient.Record(
					AnalyticsIntentProtocol.Intents.AttackStartClicked,
					spawnPointId
				)
				session.ChooseAttack()
			end))
			table.insert(uiConnections, panelReferences.MoneyButton.Activated:Connect(function()
				AnalyticsIntentClient.Record(
					AnalyticsIntentProtocol.Intents.MonsterUpgradeClicked,
					spawnPointId
				)
				session.ChooseUpgrade()
			end))
			table.insert(uiConnections, panelReferences.DiamondButton.Activated:Connect(function()
				AnalyticsIntentClient.Record(
					AnalyticsIntentProtocol.Intents.MonsterUpgradeClicked,
					spawnPointId
				)
				session.ChooseDiamondUpgrade()
			end))
			if robuxButton then
				table.insert(uiConnections, robuxButton.Activated:Connect(function()
					if robuxPromptBusy or not boundSpawnPointId then
						return
					end
					local state = session.GetState()
					local paidUpgrade = state.Snapshot and state.Snapshot.RobuxUpgrade
					local productId = if type(paidUpgrade) == "table"
						then paidUpgrade.ProductId
						else nil
					if type(productId) ~= "number" or productId <= 0 then
						TipBlackController.ShowMessage("Paid upgrade is not configured yet.")
						return
					end
					local targetId = boundSpawnPointId
					robuxPromptBusy = true
					robuxPromptProductId = productId
					robuxPromptSpawnPointId = targetId
					setButtonEnabled(robuxButton, false)
					task.spawn(function()
						local prepared = PaidPurchaseRemoteClient.PrepareMonsterUpgrade(targetId)
						if not prepared.Succeeded
							or type(prepared.ProductId) ~= "number"
							or prepared.ProductId <= 0
						then
							clearRobuxPromptState()
							TipBlackController.ShowMessage(
								prepared.Reason == "ProductNotConfigured"
									and "Paid upgrade is not configured yet."
									or "Paid upgrade is unavailable."
							)
							if management then
								management.Retry()
							end
							return
						end
						local prompted = pcall(function()
							MarketplaceService:PromptProductPurchase(player, prepared.ProductId)
						end)
						if not prompted then
							cancelRobuxPrompt()
							TipBlackController.ShowMessage("Unable to open purchase dialog.")
						end
					end)
				end))
			end
			session.Open(spawnPointId)
		end

		local resultEvent = PaidPurchaseRemoteClient.GetResultEvent()
		resultEvent.OnClientEvent:Connect(function(result)
			if type(result) ~= "table"
				or result.Kind ~= PaidPurchaseProtocol.ResultKinds.PurchaseGranted
				or result.ProductKind ~= "MonsterUpgradeToMax"
			then
				return
			end
			clearRobuxPromptState()
			if boundSpawnPointId == result.SpawnPointId then
				SoundController.Play("Yes")
				if management then
					management.Retry()
				end
			end
		end)
		MarketplaceService.PromptProductPurchaseFinished:Connect(function(
			finishedPlayer,
			productId,
			isPurchased
		)
			if finishedPlayer == player
				and not isPurchased
				and productId == robuxPromptProductId
			then
				cancelRobuxPrompt()
			end
		end)

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
			local nearestCandidate: TargetCandidate? = nil
			local nearestDistance = math.huge

			local function consider(candidate: TargetCandidate)
				if not root or not root:IsA("BasePart") then
					return
				end
				local distance = MonsterIncubatorUIPlacement.HorizontalDistance(
					root.Position,
					candidate.Position
				)
				if distance <= MonsterIncubatorUIPresentationConfig.HorizontalActivationDistance
					and distance < nearestDistance
				then
					nearestCandidate = candidate
					nearestDistance = distance
				end
			end

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
						then LocalMonsterIncubatorUIAccess.ResolveWorld(incubator)
						else nil
					if incubator and resolved then
						consider({
							Kind = "Attack",
							SpawnPointId = definition.SpawnPointId,
							Incubator = incubator,
							References = resolved,
							DefenseMonster = nil,
							Position = resolved.Glass.Position,
						})
					end
				end

				local runtime = plot:FindFirstChild("Runtime")
				local monsterRoot = runtime and runtime:FindFirstChild("Monsters")
				if monsterRoot and monsterRoot:IsA("Folder") then
					for _, child in monsterRoot:GetChildren() do
						local spawnPointId = child:GetAttribute("MonsterSpawnPointId")
						if child:IsA("Model")
							and child:GetAttribute("MonsterOwnerUserId") == player.UserId
							and child:GetAttribute("MonsterRole") == "Defense"
							and child:GetAttribute("MonsterState") == "IdleAtSpawn"
							and type(spawnPointId) == "string"
							and DefenseMonsterSlotCatalog.Get(spawnPointId) ~= nil
						then
							consider({
								Kind = "Defense",
								SpawnPointId = spawnPointId,
								Incubator = nil,
								References = nil,
								DefenseMonster = child,
								Position = child:GetPivot().Position,
							})
						end
					end
				end
			end

			if nearestCandidate then
				bindTarget(
					nearestCandidate.SpawnPointId,
					nearestCandidate.Kind,
					nearestCandidate.Incubator,
					nearestCandidate.References,
					nearestCandidate.DefenseMonster,
					nearestCandidate.Position
				)
			elseif boundIncubator or boundDefenseMonster then
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
				management.UpdateBalance(balance, "Money")
			end
		end)
		player:GetAttributeChangedSignal(DiamondProtocol.BalanceAttributeName):Connect(function()
			local balance = player:GetAttribute(DiamondProtocol.BalanceAttributeName)
			if management and type(balance) == "number" then
				management.UpdateBalance(balance, "Diamond")
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
