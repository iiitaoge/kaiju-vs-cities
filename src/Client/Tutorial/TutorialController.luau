--[[
	职责：轮询服务器权威引导步骤，解析本地场景目标并驱动 Tip + Beam 表现。
	输入：Start 无参数；状态来自 TutorialSnapshot 和攻击选择 HUD 可见性。
	输出：未完成玩家的英文引导；首次完成时短暂显示完成提示后清理，并提供完成提示结束信号。
	内部算法：服务端步骤 → 本地 ChooseTarget 子步骤 → 目标 BasePart → TutorialPresentation。
	不负责：修改金钱/区域/怪兽、提交攻击、判定完成或写入存档。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayerCityRuntimeAccess = require(
	script.Parent.Parent.Building.LocalPlayerCityRuntimeAccess
)
local LocalPlotButtonAccess = require(script.Parent.Parent.Button.LocalPlotButtonAccess)
local LocalAttackSelectionHUDAccess = require(
	script.Parent.Parent.Monster.LocalAttackSelectionHUDAccess
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
	then
		return nil
	end
	return response
end

local function resolveDefinition(stepId: string, response)
	local definition = assert(TutorialProgression.GetDefinition(stepId))
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
	if targetKind == "R1Building" then
		return findModelPart(LocalPlayerCityRuntimeAccess.FindBuilding(plot, "R1-H1"))
	end
	if targetKind == "FirstMonsterButton" then
		return findModelPart(LocalPlotButtonAccess.FindInPlot(
			plot,
			"M1",
			"M1-S1-Button"
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

local function resolveLocalStep(serverStepId: string, playerGui: PlayerGui): string
	if serverStepId ~= "StartAttack" then
		return serverStepId
	end
	local refs = LocalAttackSelectionHUDAccess.Resolve(playerGui)
	if refs and refs.Root.Visible and refs.BrowseControls.Visible then
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

			local stepId = resolveLocalStep(response.StepId, playerGui)
			local definition = resolveDefinition(stepId, response)
			local plot = LocalPlayerCityRuntimeAccess.FindPlot(player.UserId)
			local target = if plot then resolveTarget(definition.TargetKind, plot) else nil
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
