--[[
	职责：维护 HUD.Right.Attack 打开的已建造哥斯拉攻击列表。
	输入：Start；服务器怪兽管理快照；Unit 的 SpawnPointId Attribute。
	输出：新手引导完成提示结束后显示攻击入口；克隆已建造 Unit、显示 Lv.x、响应 Start.Button，
		并复用正式攻击选择 HUD。
	内部算法：打开列表时按 MonsterSpawnPointCatalog 顺序查询快照；Built=true 才克隆 Unit；
		点击后隐藏 Destroy，调用 AttackSelectionHUDController.Open；取消或不可用时恢复列表。
	不负责：创建怪兽、升级、目标查询、攻击坐标校验或攻击服务器请求。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackSelectionHUDController = require(script.Parent.AttackSelectionHUDController)
local LocalMonsterAttackRosterUIAccess = require(
	script.Parent.LocalMonsterAttackRosterUIAccess
)
local MonsterManagementRemoteClient = require(script.Parent.MonsterManagementRemoteClient)
local TutorialController = require(script.Parent.Parent.Tutorial.TutorialController)
local LocalUIVisibilityGate = require(script.Parent.Parent.UI.LocalUIVisibilityGate)
local LocalGuiButtonState = require(
	script.Parent.Parent.UI.LocalGuiButtonState
)
local LocalCombatVisibilityService = require(
	script.Parent.Parent.UI.LocalCombatVisibilityService
)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)

local MonsterAttackRosterUIController = {}

local UNIT_CLONE_ATTRIBUTE = "LocalMonsterAttackRosterUnit"
local started = false

local function setButtonEnabled(button: GuiButton, enabled: boolean)
	LocalGuiButtonState.SetEnabled(button, enabled)
end

local function requireUnitChild(
	unit: Instance,
	name: string,
	className: string,
	path: string
): Instance
	local child = unit:FindFirstChild(name)
	assert(
		child and child:IsA(className),
		string.format(
			"攻击列表 Unit 缺少 %s：%s",
			className,
			path
		)
	)
	return child
end

function MonsterAttackRosterUIController.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
		local references, reason = LocalMonsterAttackRosterUIAccess.Wait(playerGui)
		if not references then
			warn("怪兽攻击列表 UI 初始化失败：" .. tostring(reason))
			return
		end

		local unitTemplate = references.UnitTemplate
		unitTemplate.Visible = false

		local panelDesiredVisible = false
		local combatAllowsGameplay = not LocalCombatVisibilityService.IsActive()
		local refreshToken = 0
		local attackOpening = false

		local panelVisibility = LocalUIVisibilityGate.Create(
			UIModeVisibilityRules.Channels.Gameplay,
			function(visible)
				references.DestroyPanel.Visible = visible and combatAllowsGameplay
			end,
			false
		)
		local attackButtonVisibility = LocalUIVisibilityGate.Create(
			UIModeVisibilityRules.Channels.Gameplay,
			function(visible)
				references.AttackButton.Visible = visible and combatAllowsGameplay
			end,
			false
		)
		LocalCombatVisibilityService.Observe(function(active)
			combatAllowsGameplay = not active
			panelVisibility:Refresh()
			attackButtonVisibility:Refresh()
		end)

		local function clearClonedUnits()
			for _, child in references.ScrollingFrame:GetChildren() do
				if child:GetAttribute(UNIT_CLONE_ATTRIBUTE) == true then
					child:Destroy()
				end
			end
		end

		local function nextRefreshToken(): number
			refreshToken += 1
			return refreshToken
		end

		local function isCurrentRefresh(token: number): boolean
			return token == refreshToken and panelDesiredVisible
		end

		local function showPanel()
			panelDesiredVisible = true
			panelVisibility:SetDesiredVisible(true)
			local token = nextRefreshToken()
			task.spawn(function()
				clearClonedUnits()
				for index, definition in MonsterSpawnPointCatalog.GetAll() do
					if not isCurrentRefresh(token) then
						return
					end

					local response = MonsterManagementRemoteClient.GetSnapshot(
						definition.SpawnPointId
					)
					if not isCurrentRefresh(token) then
						return
					end
					local snapshot = if type(response) == "table"
						and response.Succeeded == true
						and type(response.Snapshot) == "table"
						and response.Snapshot.Built == true
						then response.Snapshot
						else nil
					if not snapshot then
						continue
					end

					local unit = unitTemplate:Clone()
					unit.Name = unitTemplate.Name
					unit:SetAttribute(UNIT_CLONE_ATTRIBUTE, true)
					unit:SetAttribute("SpawnPointId", definition.SpawnPointId)
					unit.LayoutOrder = index
					unit.Visible = true

					local level = requireUnitChild(
						unit,
						"Level",
						"TextLabel",
						"Unit.Level"
					) :: TextLabel
					level.Text = "Lv." .. tostring(snapshot.Level)

					local start = requireUnitChild(unit, "Start", "GuiObject", "Unit.Start")
					local startButton = requireUnitChild(
						start,
						"Button",
						"GuiButton",
						"Unit.Start.Button"
					) :: GuiButton
					local attackAllowed = type(snapshot.Attack) == "table"
						and snapshot.Attack.Allowed == true
					setButtonEnabled(startButton, attackAllowed)
					startButton.Activated:Connect(function()
						if attackOpening or not attackAllowed then
							return
						end
						attackOpening = true
						setButtonEnabled(startButton, false)
						local response = MonsterManagementRemoteClient.GetSnapshot(
							definition.SpawnPointId
						)
						local currentSnapshot = if type(response) == "table"
							and response.Succeeded == true
							and type(response.Snapshot) == "table"
							then response.Snapshot
							else nil
						local currentAttackAllowed = currentSnapshot ~= nil
							and type(currentSnapshot.Attack) == "table"
							and currentSnapshot.Attack.Allowed == true
						if not currentAttackAllowed then
							attackOpening = false
							showPanel()
							return
						end
						panelDesiredVisible = false
						nextRefreshToken()
						panelVisibility:SetDesiredVisible(false)
						local session = AttackSelectionHUDController.Open(
							definition.SpawnPointId,
							{
								OnAccepted = function()
									attackOpening = false
								end,
								OnCancelled = function()
									attackOpening = false
									showPanel()
								end,
								OnUnavailable = function(unavailableReason)
									attackOpening = false
									warn("攻击选择不可用：" .. tostring(unavailableReason))
									showPanel()
								end,
							}
						)
						if not session then
							attackOpening = false
							if not panelDesiredVisible then
								showPanel()
							end
						end
					end)
					unit.Parent = references.ScrollingFrame
				end
			end)
		end

		local function hidePanel()
			panelDesiredVisible = false
			nextRefreshToken()
			panelVisibility:SetDesiredVisible(false)
		end

		references.AttackButton.Activated:Connect(showPanel)
		references.CloseButton.Activated:Connect(hidePanel)
		hidePanel()
		task.spawn(function()
			TutorialController.WaitUntilComplete()
			if playerGui.Parent then
				attackButtonVisibility:SetDesiredVisible(true)
			end
		end)
	end)
end

return MonsterAttackRosterUIController
