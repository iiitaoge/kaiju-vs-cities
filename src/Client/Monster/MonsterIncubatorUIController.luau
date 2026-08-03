--[[
	职责：把 Plot1 培养罐上的 MonsterUI 接到现有怪兽管理与攻击选择链。
	输入：本地玩家的 M1-S1 运行时培养罐和服务器管理快照。
	输出：标题、现金升级价格、Start/升级按钮状态及点击请求。
	内部算法：定位服务器克隆的培养罐，组合管理状态机；怪兽回到 IdleAtSpawn 时重新打开。
	不负责：创建 UI、美术布局、扣款、升级模型、选择攻击目标或 Robux 购买。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalMonsterBuildPresentationAccess = require(script.Parent.LocalMonsterBuildPresentationAccess)
local LocalMonsterIncubatorUIAccess = require(script.Parent.LocalMonsterIncubatorUIAccess)
local MonsterManagementCoordinator = require(script.Parent.MonsterManagementCoordinator)
local PlayerMonsterAttackSelectionCoordinator = require(
	script.Parent.PlayerMonsterAttackSelectionCoordinator
)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)

local MonsterIncubatorUIController = {}

local SPAWN_POINT_ID = "M1-S1"
local PLOT_WAIT_TIMEOUT = 20
local BUILD_RETRY_DELAY = 0.25
local started = false

local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
end

function MonsterIncubatorUIController.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		local player = Players.LocalPlayer
		local plot = LocalMonsterBuildPresentationAccess.WaitForPlot(
			player.UserId,
			PLOT_WAIT_TIMEOUT
		)
		if not plot then
			warn("怪兽培养罐 UI：找不到本地玩家 Plot")
			return
		end

		local boundIncubator: Model? = nil
		local references: LocalMonsterIncubatorUIAccess.References? = nil
		local management = nil
		local currentMonster: Model? = nil
		local uiConnections: { RBXScriptConnection } = {}
		local monsterConnections: { RBXScriptConnection } = {}
		local retryToken = 0
		local refreshScheduled = false

		local function disconnectAll(connections: { RBXScriptConnection })
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
		end

		local function render(state)
			local refs = references
			if not refs then
				return
			end
			local snapshot = state.Snapshot
			local visible = state.Mode == "Managing"
				or state.Mode == "Upgrading"
				or state.Mode == "SelectingAttack"
			refs.Gui.Enabled = visible
			refs.Robux.Visible = false
			refs.StartValue.Text = if state.Mode == "SelectingAttack" then "Select Target" else "Start"

			if snapshot then
				local definition = snapshot.MonsterKey and MonsterCatalog.Get(snapshot.MonsterKey)
				local displayName = if definition then definition.DisplayName else "Monster"
				refs.Title.Text = string.format("%s · Lv %d", displayName, snapshot.Level)
				refs.MoneyValue.Text = if snapshot.Upgrade.Reason == "MaxLevel"
					then "MAX"
					else tostring(snapshot.Upgrade.Cost)
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
			if management then
				management.Close()
			end
			if references and references.Gui.Parent then
				references.Gui.Enabled = false
			end
			management = nil
			references = nil
			boundIncubator = nil
		end

		local function bindIncubator(incubator: Model)
			if boundIncubator == incubator then
				return
			end
			unbindIncubator()
			local resolved = LocalMonsterIncubatorUIAccess.Resolve(incubator)
			if not resolved then
				-- 培养罐首次复制到客户端时，后代会分帧到达；后续 DescendantAdded 会重试。
				return
			end
			boundIncubator = incubator
			references = resolved
			resolved.Gui.Enabled = false
			resolved.Robux.Visible = false
			management = MonsterManagementCoordinator.Create({
				Render = render,
				OpenAttackSelection = PlayerMonsterAttackSelectionCoordinator.Open,
			})
			local session = management
			table.insert(uiConnections, resolved.StartButton.Activated:Connect(function()
				session.ChooseAttack()
			end))
			table.insert(uiConnections, resolved.MoneyButton.Activated:Connect(function()
				session.ChooseUpgrade()
			end))
			session.Open(SPAWN_POINT_ID)
		end

		local function handleMonsterState()
			if not currentMonster or not management then
				return
			end
			local monsterState = currentMonster:GetAttribute("MonsterState")
			local mode = management.GetState().Mode
			if monsterState == "IdleAtSpawn" and mode == "Closed" then
				management.Open(SPAWN_POINT_ID)
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
						bindMonster(LocalMonsterBuildPresentationAccess.FindMonsterForSpawnPoint(
							plot,
							SPAWN_POINT_ID,
							player.UserId
						))
					end)
				end
			end))
			handleMonsterState()
		end

		local function refreshRuntimeBindings()
			local incubator = LocalMonsterBuildPresentationAccess.FindIncubator(
				plot,
				SPAWN_POINT_ID,
				player.UserId
			)
			if incubator then
				bindIncubator(incubator)
			elseif boundIncubator then
				unbindIncubator()
			end
			local monster = LocalMonsterBuildPresentationAccess.FindMonsterForSpawnPoint(
				plot,
				SPAWN_POINT_ID,
				player.UserId
			)
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
		refreshRuntimeBindings()
	end)
end

return MonsterIncubatorUIController
