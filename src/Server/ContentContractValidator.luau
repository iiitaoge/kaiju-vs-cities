--[[
	职责：在服务器启动时验证 Zone、房屋、出生点、怪兽、升级和 Boost 配置的交叉引用。
	输入：Validate/AssertValid 无参数，读取当前静态配置。
	输出：Validate 返回 Valid 和 Errors；AssertValid 在不合法时终止启动。
	内部算法：按 Catalog 遍历稳定身份，检查 Slot Kind、所属 Zone、等级连续性和 MonsterKey。
	不负责：Workspace 场景实例、玩家状态、价格平衡或运行时模型。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IncomeZoneBoostConfigs = require(script.Parent.IncomeZoneBoostConfigs)
local DefenseMonsterTemplateResolver = require(script.Parent.DefenseMonsterTemplateResolver)
local MonsterIncubatorTemplateAccess = require(script.Parent.MonsterIncubatorTemplateAccess)
local MonsterTemplateResolver = require(script.Parent.MonsterTemplateResolver)
local RegionEconomyConfigs = require(script.Parent.RegionEconomyConfigs)
local RegionUpgradeConfigs = require(script.Parent.RegionUpgradeConfigs)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local BuildingPresentationConfigs = require(
	ReplicatedStorage.Shared.Building.BuildingPresentationConfigs
)
local IncomeBuildingProgressionRules = require(
	ReplicatedStorage.Shared.Building.IncomeBuildingProgressionRules
)
local StructureDurabilityConfigs = require(
	ReplicatedStorage.Shared.Building.StructureDurabilityConfigs
)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local DefenseMonsterEconomyConfigs = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterEconomyConfigs
)
local MonsterIncubatorConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterIncubatorConfigs
)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local ContentContractValidator = {}

local function add(errors, condition: boolean, message: string)
	if not condition then
		table.insert(errors, message)
	end
end

local function resolveHouseTemplate(house, modelLevel: number): Instance?
	local segments = { house.ModelRoot, house.GroupName }
	if house.VariantName then
		table.insert(segments, house.VariantName)
	end
	table.insert(segments, "level" .. modelLevel)
	return InstancePath.Find(table.concat(segments, "/"))
end

function ContentContractValidator.Validate()
	local errors = {}
	for _, zone in ZoneCatalog.GetAll() do
		if zone.Kind == "Income" then
			add(errors, RegionEconomyConfigs[zone.ZoneId] ~= nil, zone.ZoneId .. " 缺少经济配置")
			add(errors, RegionUpgradeConfigs[zone.ZoneId] ~= nil, zone.ZoneId .. " 缺少升级配置")
			add(errors, IncomeZoneBoostConfigs[zone.ZoneId] ~= nil, zone.ZoneId .. " 缺少 Boost 配置")
		end
	end

	for regionId in RegionEconomyConfigs do
		local zone = ZoneCatalog.Get(regionId)
		add(errors, zone ~= nil and zone.Kind == "Income", regionId .. " 经济配置未指向 Income Zone")
	end
	for regionId in IncomeZoneBoostConfigs do
		local zone = ZoneCatalog.Get(regionId)
		add(errors, zone ~= nil and zone.Kind == "Income", regionId .. " Boost 配置未指向 Income Zone")
	end
	for regionId, upgrade in RegionUpgradeConfigs do
		local zone = ZoneCatalog.Get(regionId)
		add(errors, zone ~= nil and zone.Kind == "Income", regionId .. " 升级配置未指向 Income Zone")
		local maxLevel = 0
		for level in upgrade.Levels do
			if type(level) == "number" and level % 1 == 0 and level > maxLevel then
				maxLevel = level
			end
		end
		for level = 1, maxLevel do
			add(errors, upgrade.Levels[level] ~= nil, string.format("%s 缺少升级等级 %d", regionId, level))
			add(
				errors,
				StructureDurabilityConfigs.GetMaxHealth(regionId, level) ~= nil,
				string.format("%s 缺少等级 %d 耐久", regionId, level)
			)
		end
	end

	for _, house in HouseCatalog.GetAll() do
		local zone = ZoneCatalog.Get(house.RegionId)
		local slot = zone and zone.Slots[house.HouseId]
		add(errors, zone ~= nil and zone.Kind == "Income", house.HouseId .. " 未指向 Income Zone")
		add(errors, slot ~= nil and slot.Kind == "IncomeBuilding", house.HouseId .. " 缺少 IncomeBuilding Slot")

		local upgrade = RegionUpgradeConfigs[house.RegionId]
		if upgrade then
			for regionLevel in upgrade.Levels do
				local modelLevel = IncomeBuildingProgressionRules.ResolveModelLevel(
					regionLevel,
					house.BuildAtRegionLevel,
					house.RegionLevelsPerModelLevel,
					house.MaxModelLevel
				)
				if not modelLevel then
					continue
				end
				local template = resolveHouseTemplate(house, modelLevel)
				add(
					errors,
					template ~= nil and template:IsA("Model"),
					string.format(
						"%s 在区域等级 %d 缺少模型等级 %d 模板",
						house.HouseId,
						regionLevel,
						modelLevel
					)
				)
			end
		end
	end

	for _, zone in ZoneCatalog.GetAll() do
		if zone.Kind ~= "Income" then
			continue
		end
		for slotId, slot in zone.Slots do
			if slot.Kind == "IncomeBuilding" then
				local house = HouseCatalog.Get(slotId)
				add(
					errors,
					house ~= nil and house.RegionId == zone.ZoneId,
					slotId .. " 没有同 Zone 房屋配置"
				)
			end
		end
	end

	for _, spawnPoint in MonsterSpawnPointCatalog.GetAll() do
		local zone = ZoneCatalog.Get(spawnPoint.ZoneId)
		local slot = zone and zone.Slots[spawnPoint.SlotId]
		add(errors, zone ~= nil and zone.Kind == "MonsterSpawn", spawnPoint.SpawnPointId .. " 未指向 MonsterSpawn Zone")
		add(errors, slot ~= nil and slot.Kind == "MonsterSpawnPoint", spawnPoint.SpawnPointId .. " 缺少 MonsterSpawnPoint Slot")
		local incubatorConfig = MonsterIncubatorConfigs[spawnPoint.SpawnPointId]
		add(errors, incubatorConfig ~= nil, spawnPoint.SpawnPointId .. " 缺少罐体配置")
		if incubatorConfig then
			add(
				errors,
				incubatorConfig.ZoneId == spawnPoint.ZoneId,
				spawnPoint.SpawnPointId .. " 罐体 ZoneId 不匹配"
			)
			add(
				errors,
				type(incubatorConfig.IncubatorSlotId) == "string"
					and incubatorConfig.IncubatorSlotId ~= "",
				spawnPoint.SpawnPointId .. " 缺少罐体定位 SlotId"
			)
			add(
				errors,
				BuildingPresentationConfigs[incubatorConfig.PresentationId] ~= nil,
				spawnPoint.SpawnPointId .. " 缺少罐体建造表现配置"
			)
			local templateRoot = ReplicatedStorage:FindFirstChild(
				incubatorConfig.TemplateRootName
			)
			add(
				errors,
				type(incubatorConfig.TemplateIdsByForm) == "table",
				spawnPoint.SpawnPointId .. " 缺少形态到罐体模板映射"
			)
			if type(incubatorConfig.TemplateIdsByForm) == "table" then
				for formIndex, templateId in incubatorConfig.TemplateIdsByForm do
					local template = nil
					local templateReason = nil
					if templateRoot and templateRoot:IsA("Folder") then
						template, templateReason = MonsterIncubatorTemplateAccess.Resolve(
							templateRoot,
							templateId
						)
					else
						templateReason = "MissingIncubatorTemplateRoot"
					end
					add(
						errors,
						template ~= nil,
						string.format(
							"%s 形态 %s 罐体模板无效：%s",
							spawnPoint.SpawnPointId,
							tostring(formIndex),
							templateReason or "Unknown"
						)
					)
				end
			end
		end

		local maxLevel = MonsterSpawnPointCatalog.GetMaxLevel(spawnPoint.SpawnPointId) or 0
		add(errors, maxLevel >= 1, spawnPoint.SpawnPointId .. " 缺少怪兽成长等级")
		for level = 1, maxLevel do
			local monsterKey = MonsterSpawnPointCatalog.GetMonsterKey(spawnPoint.SpawnPointId, level)
			add(errors, monsterKey ~= nil, string.format("%s 缺少怪兽等级 %d", spawnPoint.SpawnPointId, level))
			if monsterKey then
				local monster = MonsterCatalog.Get(monsterKey)
				add(errors, monster ~= nil, spawnPoint.SpawnPointId .. " 引用了未知 MonsterKey " .. monsterKey)
				if monster then
					add(
						errors,
						incubatorConfig ~= nil
							and type(incubatorConfig.TemplateIdsByForm) == "table"
							and type(incubatorConfig.TemplateIdsByForm[monster.FormIndex]) == "string",
						string.format(
							"%s 的怪兽形态 %d 缺少罐体模板",
							spawnPoint.SpawnPointId,
							monster.FormIndex
						)
					)
					local template, _, modelScale, templateReason =
						MonsterTemplateResolver.Resolve(monsterKey)
					add(
						errors,
						template ~= nil and modelScale ~= nil,
						monsterKey .. " 模板无效：" .. (templateReason or "Unknown")
					)
				end
			end
		end
	end

	local defenseProgressions = {}
	for _, defenseMonster in DefenseMonsterSlotCatalog.GetAll() do
		local zone = ZoneCatalog.Get(defenseMonster.RegionId)
		add(
			errors,
			zone ~= nil and zone.Kind == "Income",
			defenseMonster.SpawnPointId .. " 未指向 Income Zone"
		)
		local maxLevel = DefenseMonsterSlotCatalog.GetMaxLevel(defenseMonster.SpawnPointId) or 0
		add(errors, maxLevel >= 1, defenseMonster.SpawnPointId .. " 缺少怪兽成长等级")
		local economy = DefenseMonsterEconomyConfigs[defenseMonster.SpawnPointId]
		add(errors, economy ~= nil, defenseMonster.SpawnPointId .. " 缺少防守怪兽经济配置")
		if economy then
			add(
				errors,
				type(economy.BuildCost) == "number"
					and economy.BuildCost >= 0
					and economy.BuildCost < math.huge,
				defenseMonster.SpawnPointId .. " 防守怪兽建造价格无效"
			)
		end
		defenseProgressions[defenseMonster.ProgressionId] = true
	end
	for _, monster in MonsterCatalog.GetAll() do
		if not defenseProgressions[monster.ProgressionId] then
			continue
		end
		local template, _, modelScale, reason =
			DefenseMonsterTemplateResolver.Resolve(monster.MonsterKey)
		add(
			errors,
			template ~= nil and modelScale ~= nil,
			monster.MonsterKey .. " 防守模板无效：" .. (reason or "Unknown")
		)
	end

	return { Valid = #errors == 0, Errors = errors }
end

function ContentContractValidator.AssertValid(): boolean
	local result = ContentContractValidator.Validate()
	assert(result.Valid, "内容合同无效：\n" .. table.concat(result.Errors, "\n"))
	return true
end

return ContentContractValidator
