--[[
	职责：协调一个服务器权威罐体的创建、房屋式建造表现和回滚。
	输入：在线 Player、所属 Plot、SpawnPointId、怪兽 FormIndex；Build 广播逐零件建造，Restore 直接恢复，Replace 换罐。
	输出：Succeeded、稳定 Reason 和已进入 Runtime 的 Incubator Model。
	内部算法：组合配置、模板/定位/Runtime Access、Factory 和表现发布器；
		服务器模型直接位于最终 Pivot，客户端隐藏权威模型并复用房屋逐零件建造表现；失败删除半成品。
	不负责：扣款、保存 Built、创建/升级怪兽、决定换罐时机、攻击或罐体开合。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterBuildPresentationPublisher = require(
	script.Parent.MonsterBuildPresentationPublisher
)
local MonsterIncubatorFactory = require(script.Parent.MonsterIncubatorFactory)
local MonsterIncubatorTemplateAccess = require(script.Parent.MonsterIncubatorTemplateAccess)
local WorkspaceMonsterIncubatorAccess = require(script.Parent.WorkspaceMonsterIncubatorAccess)
local WorkspaceMonsterIncubatorSlotAccess = require(
	script.Parent.WorkspaceMonsterIncubatorSlotAccess
)
local BuildingPresentationConfigs = require(
	ReplicatedStorage.Shared.Building.BuildingPresentationConfigs
)
local BuildPresentationVisibility = require(
	ReplicatedStorage.Shared.Building.BuildPresentationVisibility
)
local BuildPresentationTiming = require(
	ReplicatedStorage.Shared.Building.BuildPresentationTiming
)
local MonsterIncubatorConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorConfigs
)
local PlayerRebirthBonusQuery = require(script.Parent.PlayerRebirthBonusQuery)

local MonsterIncubatorBuildCoordinator = {}

export type Result = {
	Succeeded: boolean,
	Reason: string?,
	Incubator: Model?,
}

local function result(succeeded: boolean, reason: string?, incubator: Model?): Result
	return {
		Succeeded = succeeded,
		Reason = reason,
		Incubator = incubator,
	}
end

local function resolveInputs(
	plot: Model,
	spawnPointId: string,
	formIndex: number,
	requireVacant: boolean
)
	local config = MonsterIncubatorConfigs[spawnPointId]
	if not config then
		return nil, nil, nil, nil, nil, "IncubatorConfigUnavailable"
	end
	if type(formIndex) ~= "number" or formIndex < 1 or formIndex % 1 ~= 0 then
		return nil, nil, nil, nil, nil, "InvalidMonsterFormIndex"
	end
	local templateId = config.TemplateIdsByForm[formIndex]
	if type(templateId) ~= "string" or templateId == "" then
		return nil, nil, nil, nil, nil, "IncubatorTemplateNotConfiguredForForm"
	end
	local templateRoot = ReplicatedStorage:FindFirstChild(config.TemplateRootName)
	if not templateRoot or not templateRoot:IsA("Folder") then
		return nil, nil, nil, nil, nil, "MissingIncubatorTemplateRoot"
	end
	local template, templateReason = MonsterIncubatorTemplateAccess.Resolve(
		templateRoot,
		templateId
	)
	if not template then
		return nil, nil, nil, nil, nil, templateReason or "IncubatorTemplateUnavailable"
	end
	local slot, slotReason = WorkspaceMonsterIncubatorSlotAccess.Resolve(
		plot,
		config.ZoneId,
		config.IncubatorSlotId
	)
	if not slot then
		return nil, nil, nil, nil, nil, slotReason or "IncubatorSlotUnavailable"
	end
	local presentation = BuildingPresentationConfigs[config.PresentationId]
	if not presentation then
		return nil, nil, nil, nil, nil, "IncubatorBuildPresentationUnavailable"
	end
	local existing = WorkspaceMonsterIncubatorAccess.GetRoot(plot)
	if requireVacant and existing and existing:FindFirstChild(spawnPointId) then
		return nil, nil, nil, nil, nil, "MonsterIncubatorAlreadyExists"
	end
	return config, template, templateId, slot, presentation, nil
end

-- 输入：Plot、SpawnPointId 和目标怪兽 FormIndex。
-- 输出：目标罐体放入 Slot 后，其 MonsterHomeAttachment 对应的世界 CFrame。
-- 内部算法：保留模板内 Home 相对模板 Pivot 的变换，再映射到运行时 Slot Pivot。
function MonsterIncubatorBuildCoordinator.ResolveHomeCFrame(
	plot: Model,
	spawnPointId: string,
	formIndex: number
): (CFrame?, string?)
	local _, template, _, slot, _, reason = resolveInputs(
		plot,
		spawnPointId,
		formIndex,
		false
	)
	if not template or not slot then
		return nil, reason or "MonsterIncubatorHomeUnavailable"
	end
	local base = template:FindFirstChild("Base")
	local home = base and base:FindFirstChild("MonsterHomeAttachment")
	if not home or not home:IsA("Attachment") then
		return nil, "InvalidMonsterHomeAttachment"
	end
	local homeFromTemplatePivot = template:GetPivot():ToObjectSpace(home.WorldCFrame)
	return slot.CFrame * homeFromTemplatePivot, nil
end

function MonsterIncubatorBuildCoordinator.Validate(
	plot: Model,
	spawnPointId: string,
	formIndex: number
): Result
	local config, template, templateId, slot, presentation, reason = resolveInputs(
		plot,
		spawnPointId,
		formIndex,
		true
	)
	if not config or not template or not templateId or not slot or not presentation then
		return result(false, reason or "MonsterIncubatorBuildUnavailable", nil)
	end
	return result(true, nil, nil)
end

local function create(
	player: Player,
	plot: Model,
	spawnPointId: string,
	formIndex: number,
	animate: boolean
): Result
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return result(false, "InvalidPlayer", nil)
	end
	if player.Parent ~= Players then
		return result(false, "PlayerUnavailable", nil)
	end
	if typeof(plot) ~= "Instance" or not plot:IsA("Model") then
		return result(false, "InvalidPlot", nil)
	end
	if plot:GetAttribute("OwnerUserId") ~= player.UserId then
		return result(false, "PlotOwnerMismatch", nil)
	end
	if type(spawnPointId) ~= "string" or spawnPointId == "" then
		return result(false, "InvalidSpawnPointId", nil)
	end

	local config, template, templateId, slot, presentation, resolveReason = resolveInputs(
		plot,
		spawnPointId,
		formIndex,
		true
	)
	if not config or not template or not templateId or not slot or not presentation then
		return result(false, resolveReason or "MonsterIncubatorBuildUnavailable", nil)
	end
	local runtimeRoot, runtimeReason = WorkspaceMonsterIncubatorAccess.GetOrCreateRoot(plot)
	if not runtimeRoot then
		return result(false, runtimeReason or "MonsterIncubatorRuntimeUnavailable", nil)
	end

	local targetCFrame = slot.CFrame
	local created, modelOrError = pcall(
		MonsterIncubatorFactory.Create,
		template,
		targetCFrame,
		runtimeRoot,
		{
			OwnerUserId = player.UserId,
			SpawnPointId = spawnPointId,
			ZoneId = config.ZoneId,
			TemplateId = templateId,
		},
		animate
	)
	if not created then
		warn(string.format(
			"创建服务器罐体失败：%s/%s (%s)",
			player.Name,
			spawnPointId,
			tostring(modelOrError)
		))
		if #runtimeRoot:GetChildren() == 0 then
			runtimeRoot:Destroy()
		end
		return result(false, "MonsterIncubatorCreateFailed", nil)
	end
	local model = modelOrError :: Model

	if animate then
		local buildSpeedMultiplier = PlayerRebirthBonusQuery.Get(player).BuildSpeedMultiplier
		local motion = MonsterBuildPresentationPublisher.PublishAndWait({
			Kind = "IncubatorBuild",
			OwnerUserId = player.UserId,
			SpawnPointId = spawnPointId,
			PresentationId = config.PresentationId,
			BuildSpeedMultiplier = buildSpeedMultiplier,
			TemplateId = templateId,
		}, BuildPresentationTiming.ScaleDuration(
			presentation.Rise.TotalDuration,
			buildSpeedMultiplier
		), function()
				return player.Parent ~= Players
					or plot.Parent == nil
					or plot:GetAttribute("OwnerUserId") ~= player.UserId
			end)
		if not motion.Succeeded then
			local _, removeReason = WorkspaceMonsterIncubatorAccess.Remove(
				plot,
				spawnPointId,
				model
			)
			if removeReason and model.Parent then
				model:Destroy()
			end
			return result(
				false,
				motion.Reason or "MonsterIncubatorBuildPresentationFailed",
				nil
			)
		end
		BuildPresentationVisibility.Restore(model)
	end

	local incubator, accessReason = WorkspaceMonsterIncubatorAccess.Resolve(
		plot,
		spawnPointId
	)
	if not incubator or incubator.Model ~= model then
		local _, removeReason = WorkspaceMonsterIncubatorAccess.Remove(
			plot,
			spawnPointId,
			model
		)
		if removeReason and model.Parent then
			model:Destroy()
		end
		return result(false, accessReason or "MonsterIncubatorValidationFailed", nil)
	end
	return result(true, nil, model)
end

function MonsterIncubatorBuildCoordinator.Build(
	player: Player,
	plot: Model,
	spawnPointId: string,
	formIndex: number
): Result
	return create(player, plot, spawnPointId, formIndex, true)
end

function MonsterIncubatorBuildCoordinator.Restore(
	player: Player,
	plot: Model,
	spawnPointId: string,
	formIndex: number
): Result
	return create(player, plot, spawnPointId, formIndex, false)
end

-- 输入：现有罐体及目标怪兽 FormIndex；hideForPresentation 控制新罐是否预隐藏。
-- 输出：已原位替换的新罐；创建失败时尽力恢复原模板并返回失败。
-- 内部算法：先完整解析新旧模板，再删除旧罐并在同一 Slot 创建新罐。
function MonsterIncubatorBuildCoordinator.Replace(
	player: Player,
	plot: Model,
	spawnPointId: string,
	formIndex: number,
	hideForPresentation: boolean
): Result
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return result(false, "InvalidPlayer", nil)
	end
	if player.Parent ~= Players then
		return result(false, "PlayerUnavailable", nil)
	end
	if typeof(plot) ~= "Instance" or not plot:IsA("Model") then
		return result(false, "InvalidPlot", nil)
	end
	if plot:GetAttribute("OwnerUserId") ~= player.UserId then
		return result(false, "PlotOwnerMismatch", nil)
	end
	if type(hideForPresentation) ~= "boolean" then
		return result(false, "InvalidPresentationVisibility", nil)
	end

	local current, currentReason = WorkspaceMonsterIncubatorAccess.Resolve(plot, spawnPointId)
	if not current then
		return result(false, currentReason or "MonsterIncubatorUnavailable", nil)
	end
	local config, template, templateId, slot, _, resolveReason = resolveInputs(
		plot,
		spawnPointId,
		formIndex,
		false
	)
	if not config or not template or not templateId or not slot then
		return result(false, resolveReason or "MonsterIncubatorReplaceUnavailable", nil)
	end
	if current.Model:GetAttribute("IncubatorTemplateId") == templateId then
		return result(true, nil, current.Model)
	end

	local previousTemplateId = current.Model:GetAttribute("IncubatorTemplateId")
	if type(previousTemplateId) ~= "string" or previousTemplateId == "" then
		return result(false, "InvalidCurrentIncubatorTemplateId", nil)
	end
	local templateRoot = ReplicatedStorage:FindFirstChild(config.TemplateRootName)
	local previousTemplate = nil
	local previousTemplateReason = nil
	if templateRoot and templateRoot:IsA("Folder") then
		previousTemplate, previousTemplateReason = MonsterIncubatorTemplateAccess.Resolve(
			templateRoot,
			previousTemplateId
		)
	else
		previousTemplateReason = "MissingIncubatorTemplateRoot"
	end
	if not previousTemplate then
		return result(false, previousTemplateReason or "CurrentIncubatorTemplateUnavailable", nil)
	end
	local runtimeRoot = WorkspaceMonsterIncubatorAccess.GetRoot(plot)
	if not runtimeRoot then
		return result(false, "MissingMonsterIncubatorRuntime", nil)
	end

	local identity = {
		OwnerUserId = player.UserId,
		SpawnPointId = spawnPointId,
		ZoneId = config.ZoneId,
		TemplateId = templateId,
	}
	local function restorePrevious(): (boolean, any)
		return pcall(
			MonsterIncubatorFactory.Create,
			previousTemplate,
			slot.CFrame,
			runtimeRoot,
			{
				OwnerUserId = player.UserId,
				SpawnPointId = spawnPointId,
				ZoneId = config.ZoneId,
				TemplateId = previousTemplateId,
			},
			false
		)
	end
	current.Model:Destroy()
	local created, modelOrError = pcall(
		MonsterIncubatorFactory.Create,
		template,
		slot.CFrame,
		runtimeRoot,
		identity,
		hideForPresentation
	)
	if not created then
		local restored, restoreError = restorePrevious()
		if not restored then
			warn("替换罐体失败且无法恢复旧罐：", restoreError)
		end
		warn("替换罐体失败：", modelOrError)
		return result(false, "MonsterIncubatorReplaceFailed", nil)
	end

	local model = modelOrError :: Model
	local incubator, accessReason = WorkspaceMonsterIncubatorAccess.Resolve(plot, spawnPointId)
	if not incubator or incubator.Model ~= model then
		if model.Parent then
			model:Destroy()
		end
		local restored, restoreError = restorePrevious()
		if not restored then
			warn("新罐验证失败且无法恢复旧罐：", restoreError)
		end
		return result(false, accessReason or "MonsterIncubatorValidationFailed", nil)
	end
	return result(true, nil, model)
end

function MonsterIncubatorBuildCoordinator.Remove(
	plot: Model,
	spawnPointId: string,
	expectedModel: Model?
): Result
	local removed, reason = WorkspaceMonsterIncubatorAccess.Remove(
		plot,
		spawnPointId,
		expectedModel
	)
	return result(removed, reason, nil)
end

return MonsterIncubatorBuildCoordinator
