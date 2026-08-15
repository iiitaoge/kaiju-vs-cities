--[[
	职责：轮询服务器权威引导步骤，解析本地场景目标并驱动 Tip、Beam 与点击引导表现。
	输入：Start 无参数；状态来自 TutorialSnapshot、攻击选择 HUD、本地攻击选择状态和怪兽管理面板显隐。
	输出：未完成玩家的英文引导；首次完成时短暂显示完成提示后清理，并提供完成提示结束信号。
	内部算法：服务端步骤 → 本地 ChooseTarget 子步骤 → 世界目标/UI 目标 → TutorialPresentation。
	不负责：修改金钱/区域/怪兽、提交攻击、判定完成或写入存档。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalPlayerCityRuntimeAccess = require(
	script.Parent.Parent.Building.LocalPlayerCityRuntimeAccess
)
local LocalPlotButtonAccess = require(script.Parent.Parent.Button.LocalPlotButtonAccess)
local LocalAttackSelectionHUDAccess = require(
	script.Parent.Parent.Monster.LocalAttackSelectionHUDAccess
)
local LocalAttackSelectionTutorialState = require(
	script.Parent.Parent.Monster.LocalAttackSelectionTutorialState
)
local LocalMonsterManagementPanelAccess = require(
	script.Parent.Parent.Monster.LocalMonsterManagementPanelAccess
)
local LocalMonsterBuildPresentationAccess = require(
	script.Parent.Parent.Monster.LocalMonsterBuildPresentationAccess
)
local LocalMonsterIncubatorUIAccess = require(
	script.Parent.Parent.Monster.LocalMonsterIncubatorUIAccess
)
local TutorialPresentation = require(script.Parent.TutorialPresentation)
local TutorialProgression = require(
	ReplicatedStorage.Shared.Tutorial.TutorialProgression
)
local TutorialProtocol = require(ReplicatedStorage.Shared.Tutorial.TutorialProtocol)
local CompactNumberFormatter = require(
	ReplicatedStorage.Shared.UI.CompactNumberFormatter
)

local TutorialController = {}

local POLL_SECONDS = 0.35
local COMPLETE_DISPLAY_SECONDS = 3.5
local started = false
local completionNotified = false
local completionEvent = Instance.new("BindableEvent")

local function notifyCompletion()
	if completionNotified then
		return
	end
	completionNotified = true
	completionEvent:Fire()
end

local function getRemote(): RemoteFunction?
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	local remote = remotes and remotes:WaitForChild(TutorialProtocol.SnapshotRemoteName, 20)
	return if remote and remote:IsA("RemoteFunction") then remote else nil
end

local function query(remote: RemoteFunction)
	local invoked, response = pcall(remote.InvokeServer, remote)
	if not invoked or type(response) ~= "table" or response.Succeeded ~= true then
		return nil
	end
	if type(response.StepId) ~= "string"
		or not TutorialProgression.GetDefinition(response.StepId)
	then
		return nil
	end
	if type(response.R1UpgradeCost) ~= "number"
		or type(response.FirstMonsterBuildCost) ~= "number"
		or type(response.FirstMonsterBuildInProgress) ~= "boolean"
		or type(response.AttackCompleted) ~= "boolean"
		or type(response.FirstDefenseMonsterBuildCost) ~= "number"
		or type(response.FirstDefenseMonsterBuilt) ~= "boolean"
	then
		return nil
	end
	return response
end

local function resolveDefinition(stepId: string, response)
	local definition = assert(TutorialProgression.GetDefinition(stepId))
	if stepId == "ChooseTarget" and UserInputService.TouchEnabled then
		local state = LocalAttackSelectionTutorialState.Get()
		return {
			Title = if state.MobileAimReady then "LAUNCH THE ATTACK" else "AIM AT THE TARGET",
			Info = if state.MobileAimReady
				then "Press Attack to launch."
				else "Tap the highlighted city to aim.",
			TargetKind = definition.TargetKind,
		}
	end
	local amountKey = definition.AmountKey
	if not amountKey then
		return definition
	end
	local amount = response[amountKey]
	assert(
		type(amount) == "number" and amount == amount and math.abs(amount) < math.huge,
		"服务器返回的引导金额无效"
	)
	return {
		Title = definition.Title,
		Info = string.format(
			definition.Info,
			"$" .. CompactNumberFormatter.Format(amount)
		),
		TargetKind = definition.TargetKind,
	}
end

local function isVisibleGuiObject(guiObject: GuiObject?): boolean
	if not guiObject then
		return false
	end
	local current: Instance? = guiObject
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
end

local function isMonsterManagementPanelVisible(playerGui: PlayerGui): boolean
	local management = LocalMonsterManagementPanelAccess.Resolve(playerGui)
	return management ~= nil and isVisibleGuiObject(management.Panel)
end

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

local function resolveTarget(targetKind: string?, plot: Model): BasePart?
	if targetKind == "R1ConstructionButton" then
		return findModelPart(LocalPlotButtonAccess.FindInPlot(
			plot,
			"R1",
			"R1-Upgrade-Button"
		))
	end
	if targetKind == "R1Building" or targetKind == "R1MonsterBuildBuilding" then
		local houseId = if targetKind == "R1MonsterBuildBuilding" then "R1-H2" else "R1-H1"
		return findModelPart(LocalPlayerCityRuntimeAccess.FindBuilding(plot, houseId))
	end
	if targetKind == "R1DefenseMonsterBuildBuilding" then
		return findModelPart(LocalPlayerCityRuntimeAccess.FindBuilding(plot, "R1-H2"))
	end
	if targetKind == "FirstMonsterButton" then
		return findModelPart(LocalPlotButtonAccess.FindInPlot(
			plot,
			"M1",
			"M1-S1-Button"
		))
	end
	if targetKind == "FirstDefenseMonsterButton" then
		return findModelPart(LocalPlotButtonAccess.FindInPlot(
			plot,
			"R1",
			"DM-R1-Button"
		))
	end
	if targetKind == "FirstMonsterIncubator" then
		local incubator = LocalMonsterBuildPresentationAccess.FindIncubator(
			plot,
			"M1-S1",
			Players.LocalPlayer.UserId
		)
		local refs = incubator and LocalMonsterIncubatorUIAccess.Resolve(incubator)
		return if refs then refs.Glass else nil
	end
	return nil
end

local function resolveGuideTarget(
	stepId: string,
	playerGui: PlayerGui,
	plot: Model?,
	targetKind: string?
): TutorialPresentation.GuideTarget?
	if stepId == "StartAttack" then
		local management = LocalMonsterManagementPanelAccess.Resolve(playerGui)
		if management
			and management.Panel.Visible
			and isVisibleGuiObject(management.StartButton)
			and management.StartButton.Active
		then
			return {
				GuiObject = management.StartButton,
				WorldPart = nil,
				WorldPosition = nil,
				WorldBounds = nil,
			}
		end
		local incubatorTarget = if plot
			then resolveTarget("FirstMonsterIncubator", plot)
			else nil
		return if incubatorTarget
			then {
				GuiObject = nil,
				WorldPart = incubatorTarget,
				WorldPosition = nil,
				WorldBounds = nil,
			}
			else nil
	end

	if stepId == "ChooseTarget" then
		local state = LocalAttackSelectionTutorialState.Get()
		if UserInputService.TouchEnabled
			and state.MobileAimReady
		then
			local attackHUD = LocalAttackSelectionHUDAccess.Resolve(playerGui)
			if attackHUD
				and isVisibleGuiObject(attackHUD.AttackButton)
				and attackHUD.AttackButton.Active
			then
				return {
					GuiObject = attackHUD.AttackButton,
					WorldPart = nil,
					WorldPosition = nil,
					WorldBounds = nil,
				}
			end
		end
		if state.WorldGuideCFrame and state.WorldGuideSize then
			return {
				GuiObject = nil,
				WorldPart = nil,
				WorldPosition = state.WorldGuideCFrame.Position,
				WorldBounds = {
					CFrame = state.WorldGuideCFrame,
					Size = state.WorldGuideSize,
				},
				ScreenCenter = true,
			}
		end
		local attackHUD = LocalAttackSelectionHUDAccess.Resolve(playerGui)
		if attackHUD and isVisibleGuiObject(attackHUD.BrowseControls) then
			return {
				GuiObject = attackHUD.BrowseControls,
				WorldPart = nil,
				WorldPosition = nil,
				WorldBounds = nil,
			}
		end
		return nil
	end

	local worldTarget = if plot then resolveTarget(targetKind, plot) else nil
	return if worldTarget
		then {
			GuiObject = nil,
			WorldPart = worldTarget,
			WorldPosition = nil,
			WorldBounds = nil,
		}
		else nil
end

local function resolveLocalStep(serverStepId: string, playerGui: PlayerGui): string
	if serverStepId ~= "StartAttack" then
		return serverStepId
	end
	local refs = LocalAttackSelectionHUDAccess.Resolve(playerGui)
	if refs and refs.Root.Visible then
		return "ChooseTarget"
	end
	return serverStepId
end

function TutorialController.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui")
		local completedVersion = player:GetAttribute(
			TutorialProtocol.CompletedVersionAttributeName
		)
		if type(completedVersion) == "number"
			and completedVersion >= TutorialProgression.CurrentVersion
		then
			notifyCompletion()
			return
		end
		local remote = getRemote()
		if not remote then
			warn("新手引导：找不到 TutorialSnapshot RemoteFunction")
			return
		end

		local presentation = nil
		local hadActiveTutorial = false
		while player.Parent do
			local response = query(remote)
			if not response then
				task.wait(POLL_SECONDS)
				continue
			end

			if response.StepId == "Complete" then
				if hadActiveTutorial and presentation then
					presentation.SetPopupVisible(
						not isMonsterManagementPanelVisible(playerGui)
					)
					presentation.Show(
						assert(TutorialProgression.GetDefinition("Complete")),
						nil
					)
					task.wait(COMPLETE_DISPLAY_SECONDS)
				end
				if presentation then
					presentation.Destroy()
				end
				notifyCompletion()
				return
			end

			hadActiveTutorial = true
			if not presentation then
				local reason
				presentation, reason = TutorialPresentation.Create(playerGui)
				if not presentation then
					warn("新手引导表现初始化失败：" .. tostring(reason))
					return
				end
			end

			presentation.SetPopupVisible(
				not isMonsterManagementPanelVisible(playerGui)
			)
			local stepId = resolveLocalStep(response.StepId, playerGui)
			local definition = resolveDefinition(stepId, response)
			local plot = LocalPlayerCityRuntimeAccess.FindPlot(player.UserId)
			local target = resolveGuideTarget(stepId, playerGui, plot, definition.TargetKind)
			presentation.Show(definition, target)
			task.wait(POLL_SECONDS)
		end
		if presentation then
			presentation.Destroy()
		end
	end)
end

-- 输入：无。
-- 输出：在新手引导完成提示展示结束后返回；已完成引导的玩家立即返回。
-- 内部算法：复用本控制器唯一的完成事件，不重复查询服务器或计算步骤。
function TutorialController.WaitUntilComplete()
	if completionNotified then
		return
	end
	completionEvent.Event:Wait()
end

return TutorialController
