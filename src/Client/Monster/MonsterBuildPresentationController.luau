--[[
	职责：播放培养罐建造、初始怪兽建造和怪兽升级表现。
	输入：MonsterBuildPresentation RemoteEvent 的协议命令。
	输出：只产生客户端临时视觉；结束后显示服务器权威模型。
	内部算法：解析 Plot/配置/模板/权威模型并本地隐藏；复用房屋拆除和升起小模块；
		首次罐体和怪兽只升起；换形态升级严格串行执行怪兽拆除、罐体拆/建、怪兽建造。
	不负责：创建服务器对象、等待业务阶段、扣款、保存、攻击开合或怪兽状态。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalBuildingDemolitionAnimation = require(
	script.Parent.Parent.Building.LocalBuildingDemolitionAnimation
)
local LocalBuildingRiseAnimation = require(
	script.Parent.Parent.Building.LocalBuildingRiseAnimation
)
local LocalBuildingVisibility = require(
	script.Parent.Parent.Building.LocalBuildingVisibility
)
local LocalMonsterBuildPresentationAccess = require(
	script.Parent.LocalMonsterBuildPresentationAccess
)
local BuildingPresentationConfigs = require(
	ReplicatedStorage.Shared.Building.BuildingPresentationConfigs
)
local BuildPresentationTiming = require(
	ReplicatedStorage.Shared.Building.BuildPresentationTiming
)
local MonsterBuildPresentationProtocol = require(
	ReplicatedStorage.Shared.Monster.MonsterBuildPresentationProtocol
)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local MonsterFormTemplateAccess = require(
	ReplicatedStorage.Shared.Monster.MonsterFormTemplateAccess
)
local MonsterIncubatorConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorConfigs
)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)

local MonsterBuildPresentationController = {}

local started = false

local function resolveMonsterTemplate(monsterKey: string): (Model, number)
	local definition = assert(MonsterCatalog.Get(monsterKey), "未知 MonsterKey：" .. monsterKey)
	local template, modelScale, reason = MonsterFormTemplateAccess.Resolve(
		definition.TemplateRoot,
		definition.FormIndex,
		definition.GrowthAlpha
	)
	assert(
		template and modelScale,
		string.format("怪兽模板不可用：%s (%s)", monsterKey, reason or "Unknown")
	)
	return template, modelScale
end

local function resolveIncubatorTemplate(config, templateId: string): Model
	local configured = false
	for _, configuredTemplateId in config.TemplateIdsByForm do
		if configuredTemplateId == templateId then
			configured = true
			break
		end
	end
	assert(configured, "培养罐模板未配置：" .. templateId)
	local templateRoot = ReplicatedStorage:FindFirstChild(config.TemplateRootName)
	local template = templateRoot and templateRoot:FindFirstChild(templateId)
	assert(template and template:IsA("Model"), "找不到培养罐模板：" .. templateId)
	return template
end

local function resolveCommon(command)
	local incubatorConfig = assert(
		MonsterIncubatorConfigs[command.SpawnPointId],
		"缺少培养罐配置：" .. command.SpawnPointId
	)
	assert(
		incubatorConfig.PresentationId == command.PresentationId,
		"培养罐表现配置不匹配：" .. command.SpawnPointId
	)
	local presentation = assert(
		BuildingPresentationConfigs[command.PresentationId],
		"缺少建造表现配置：" .. command.PresentationId
	)
	presentation = {
		ResolveTimeout = presentation.ResolveTimeout,
		Demolish = BuildPresentationTiming.ScaleMotion(
			presentation.Demolish,
			command.BuildSpeedMultiplier
		),
		Rise = BuildPresentationTiming.ScaleMotion(
			presentation.Rise,
			command.BuildSpeedMultiplier
		),
	}
	local plot = assert(
		LocalMonsterBuildPresentationAccess.WaitForPlot(
			command.OwnerUserId,
			presentation.ResolveTimeout
		),
		"找不到玩家 Plot：" .. tostring(command.OwnerUserId)
	)
	return incubatorConfig, presentation, plot
end

local function presentIncubatorBuild(command)
	local config, presentation, plot = resolveCommon(command)
	local template = resolveIncubatorTemplate(config, command.TemplateId)
	local slot = assert(
		LocalMonsterBuildPresentationAccess.FindSlot(
			plot,
			config.ZoneId,
			"IncubatorSlots",
			config.IncubatorSlotId
		),
		"找不到培养罐定位点：" .. config.IncubatorSlotId
	)
	local authoritative = assert(
		LocalMonsterBuildPresentationAccess.WaitForIncubator(
			plot,
			command.SpawnPointId,
			command.OwnerUserId,
			presentation.ResolveTimeout
		),
		"找不到服务器培养罐：" .. command.SpawnPointId
	)
	assert(
		authoritative:GetAttribute("IncubatorTemplateId") == command.TemplateId,
		"服务器培养罐模板身份不匹配：" .. command.SpawnPointId
	)
	local snapshot = LocalBuildingVisibility.Hide(authoritative)
	local succeeded, message = xpcall(function()
		LocalBuildingRiseAnimation.Play(
			template,
			authoritative:GetPivot(),
			slot.Position.Y,
			presentation.Rise
		)
	end, debug.traceback)
	LocalBuildingVisibility.Restore(snapshot)
	if not succeeded then
		error(message)
	end
end

local function resolveMonsterPresentation(command)
	local _, presentation, plot = resolveCommon(command)
	local spawnPoint = assert(
		MonsterSpawnPointCatalog.Get(command.SpawnPointId),
		"未知 SpawnPointId：" .. command.SpawnPointId
	)
	local slot = assert(
		LocalMonsterBuildPresentationAccess.FindSlot(
			plot,
			spawnPoint.ZoneId,
			"Slots",
			spawnPoint.SlotId
		),
		"找不到怪兽出生点：" .. spawnPoint.SlotId
	)
	local authoritative = assert(
		LocalMonsterBuildPresentationAccess.WaitForMonster(
			plot,
			command.SpawnPointId,
			command.OwnerUserId,
			command.MonsterKey,
			presentation.ResolveTimeout
		),
		"找不到服务器怪兽：" .. command.SpawnPointId
	)
	return presentation, slot, authoritative
end

local function presentMonsterBuild(command)
	local presentation, slot, authoritative = resolveMonsterPresentation(command)
	local template, modelScale = resolveMonsterTemplate(command.MonsterKey)
	local snapshot = LocalBuildingVisibility.Hide(authoritative)
	local succeeded, message = xpcall(function()
		LocalBuildingRiseAnimation.Play(
			template,
			authoritative:GetPivot(),
			slot.Position.Y,
			presentation.Rise,
			modelScale
		)
	end, debug.traceback)
	LocalBuildingVisibility.Restore(snapshot)
	if not succeeded then
		error(message)
	end
end

local function presentMonsterUpgrade(command)
	local config, presentation, plot = resolveCommon(command)
	local incubatorSlot = assert(
		LocalMonsterBuildPresentationAccess.FindSlot(
			plot,
			config.ZoneId,
			"IncubatorSlots",
			config.IncubatorSlotId
		),
		"找不到培养罐定位点：" .. config.IncubatorSlotId
	)
	local oldAuthoritativeIncubator = assert(
		LocalMonsterBuildPresentationAccess.WaitForIncubator(
			plot,
			command.SpawnPointId,
			command.OwnerUserId,
			presentation.ResolveTimeout
		),
		"找不到服务器培养罐：" .. command.SpawnPointId
	)
	assert(
		oldAuthoritativeIncubator:GetAttribute("IncubatorTemplateId")
			== command.PreviousIncubatorTemplateId,
		"服务器培养罐模板身份不匹配：" .. command.SpawnPointId
	)
	local oldIncubatorTemplate = resolveIncubatorTemplate(
		config,
		command.PreviousIncubatorTemplateId
	)
	local newIncubatorTemplate = resolveIncubatorTemplate(
		config,
		command.IncubatorTemplateId
	)

	local spawnPoint = assert(
		MonsterSpawnPointCatalog.Get(command.SpawnPointId),
		"未知 SpawnPointId：" .. command.SpawnPointId
	)
	local monsterSlot = assert(
		LocalMonsterBuildPresentationAccess.FindSlot(
			plot,
			spawnPoint.ZoneId,
			"Slots",
			spawnPoint.SlotId
		),
		"找不到怪兽出生点：" .. spawnPoint.SlotId
	)
	local authoritativeMonster = assert(
		LocalMonsterBuildPresentationAccess.WaitForMonster(
			plot,
			command.SpawnPointId,
			command.OwnerUserId,
			command.MonsterKey,
			presentation.ResolveTimeout
		),
		"找不到服务器怪兽：" .. command.SpawnPointId
	)
	local oldTemplate, oldModelScale = resolveMonsterTemplate(command.PreviousMonsterKey)
	local newTemplate, newModelScale = resolveMonsterTemplate(command.MonsterKey)
	local monsterPivot = authoritativeMonster:GetPivot()
	local monsterSnapshot = LocalBuildingVisibility.Hide(authoritativeMonster)
	local oldIncubatorSnapshot = nil
	local newIncubatorSnapshot = nil
	local succeeded, message = xpcall(function()
		LocalBuildingDemolitionAnimation.Play(
			oldTemplate,
			command.PreviousMonsterCFrame,
			monsterSlot.Position.Y,
			presentation.Demolish,
			oldModelScale
		)
		local oldIncubatorPivot = oldAuthoritativeIncubator:GetPivot()
		oldIncubatorSnapshot = LocalBuildingVisibility.Hide(oldAuthoritativeIncubator)
		LocalBuildingDemolitionAnimation.Play(
			oldIncubatorTemplate,
			oldIncubatorPivot,
			incubatorSlot.Position.Y,
			presentation.Demolish
		)
		local newAuthoritativeIncubator = assert(
			LocalMonsterBuildPresentationAccess.WaitForIncubatorTemplate(
				plot,
				command.SpawnPointId,
				command.OwnerUserId,
				command.IncubatorTemplateId,
				presentation.ResolveTimeout
			),
			"找不到升级后的服务器培养罐：" .. command.SpawnPointId
		)
		newIncubatorSnapshot = LocalBuildingVisibility.Hide(newAuthoritativeIncubator)
		LocalBuildingRiseAnimation.Play(
			newIncubatorTemplate,
			newAuthoritativeIncubator:GetPivot(),
			incubatorSlot.Position.Y,
			presentation.Rise
		)
		LocalBuildingVisibility.Restore(newIncubatorSnapshot)
		LocalBuildingRiseAnimation.Play(
			newTemplate,
			monsterPivot,
			monsterSlot.Position.Y,
			presentation.Rise,
			newModelScale
		)
	end, debug.traceback)
	if oldIncubatorSnapshot then
		LocalBuildingVisibility.Restore(oldIncubatorSnapshot)
	end
	if newIncubatorSnapshot then
		LocalBuildingVisibility.Restore(newIncubatorSnapshot)
	end
	LocalBuildingVisibility.Restore(monsterSnapshot)
	if not succeeded then
		error(message)
	end
end

local function present(command)
	if command.Kind == "IncubatorBuild" then
		presentIncubatorBuild(command)
	elseif command.Kind == "MonsterBuild" then
		presentMonsterBuild(command)
	else
		presentMonsterUpgrade(command)
	end
end

function MonsterBuildPresentationController.Start()
	if started then
		return
	end
	started = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild(MonsterBuildPresentationProtocol.RemoteName)
	assert(
		remote:IsA("RemoteEvent"),
		MonsterBuildPresentationProtocol.RemoteName .. " 必须是 RemoteEvent"
	)
	remote.OnClientEvent:Connect(function(command)
		local valid, reason = MonsterBuildPresentationProtocol.Validate(command)
		if not valid then
			warn("拒绝怪兽建造表现命令：" .. (reason or "Unknown"))
			return
		end
		task.spawn(function()
			local succeeded, message = xpcall(present, debug.traceback, command)
			if not succeeded then
				warn("怪兽建造表现失败：" .. tostring(message))
			end
		end)
	end)
end

return MonsterBuildPresentationController
