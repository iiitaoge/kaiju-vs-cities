--[[
	职责：协调一个服务器权威罐体的创建、房屋式建造表现和回滚。
	输入：在线 Player、所属 Plot、SpawnPointId；Build 广播逐零件建造，Restore 直接恢复。
	输出：Succeeded、稳定 Reason 和已进入 Runtime 的 Incubator Model。
	内部算法：组合配置、模板/定位/Runtime Access、Factory 和表现发布器；
		服务器模型直接位于最终 Pivot，客户端隐藏权威模型并复用房屋逐零件建造表现；失败删除半成品。
	不负责：扣款、保存 Built、创建怪兽、升级怪兽、攻击或罐体开合。
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
local MonsterIncubatorConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorConfigs
)

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

local function resolveInputs(plot: Model, spawnPointId: string)
	local config = MonsterIncubatorConfigs[spawnPointId]
	if not config then
		return nil, nil, nil, nil, "IncubatorConfigUnavailable"
	end
	local templateRoot = ReplicatedStorage:FindFirstChild(config.TemplateRootName)
	if not templateRoot or not templateRoot:IsA("Folder") then
		return nil, nil, nil, nil, "MissingIncubatorTemplateRoot"
	end
	local template, templateReason = MonsterIncubatorTemplateAccess.Resolve(
		templateRoot,
		config.TemplateId
	)
	if not template then
		return nil, nil, nil, nil, templateReason or "IncubatorTemplateUnavailable"
	end
	local slot, slotReason = WorkspaceMonsterIncubatorSlotAccess.Resolve(
		plot,
		config.ZoneId,
		config.IncubatorSlotId
	)
	if not slot then
		return nil, nil, nil, nil, slotReason or "IncubatorSlotUnavailable"
	end
	local presentation = BuildingPresentationConfigs[config.PresentationId]
	if not presentation then
		return nil, nil, nil, nil, "IncubatorBuildPresentationUnavailable"
	end
	local existing = WorkspaceMonsterIncubatorAccess.GetRoot(plot)
	if existing and existing:FindFirstChild(spawnPointId) then
		return nil, nil, nil, nil, "MonsterIncubatorAlreadyExists"
	end
	return config, template, slot, presentation, nil
end

function MonsterIncubatorBuildCoordinator.Validate(
	plot: Model,
	spawnPointId: string
): Result
	local config, template, slot, presentation, reason = resolveInputs(plot, spawnPointId)
	if not config or not template or not slot or not presentation then
		return result(false, reason or "MonsterIncubatorBuildUnavailable", nil)
	end
	return result(true, nil, nil)
end

local function create(
	player: Player,
	plot: Model,
	spawnPointId: string,
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

	local config, template, slot, presentation, resolveReason = resolveInputs(
		plot,
		spawnPointId
	)
	if not config or not template or not slot or not presentation then
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
			TemplateId = config.TemplateId,
		}
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
		local motion = MonsterBuildPresentationPublisher.PublishAndWait({
			Kind = "IncubatorBuild",
			OwnerUserId = player.UserId,
			SpawnPointId = spawnPointId,
			PresentationId = config.PresentationId,
		}, presentation.Rise.TotalDuration, function()
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
	spawnPointId: string
): Result
	return create(player, plot, spawnPointId, true)
end

function MonsterIncubatorBuildCoordinator.Restore(
	player: Player,
	plot: Model,
	spawnPointId: string
): Result
	return create(player, plot, spawnPointId, false)
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
