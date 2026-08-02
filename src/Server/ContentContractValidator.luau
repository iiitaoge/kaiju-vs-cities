--[[
	职责：在服务器启动时验证 Zone、房屋、出生点、怪兽和升级配置的交叉引用。
	输入：Validate/AssertValid 无参数，读取当前静态配置。
	输出：Validate 返回 Valid 和 Errors；AssertValid 在不合法时终止启动。
	内部算法：按 Catalog 遍历稳定身份，检查 Slot Kind、所属 Zone、等级连续性和 MonsterKey。
	不负责：Workspace 场景实例、玩家状态、价格平衡或运行时模型。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionEconomyConfigs = require(script.Parent.RegionEconomyConfigs)
local RegionUpgradeConfigs = require(script.Parent.RegionUpgradeConfigs)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
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

function ContentContractValidator.Validate()
	local errors = {}
	for _, zone in ZoneCatalog.GetAll() do
		if zone.Kind == "Income" then
			add(errors, RegionEconomyConfigs[zone.ZoneId] ~= nil, zone.ZoneId .. " 缺少经济配置")
			add(errors, RegionUpgradeConfigs[zone.ZoneId] ~= nil, zone.ZoneId .. " 缺少升级配置")
		end
	end

	for regionId in RegionEconomyConfigs do
		local zone = ZoneCatalog.Get(regionId)
		add(errors, zone ~= nil and zone.Kind == "Income", regionId .. " 经济配置未指向 Income Zone")
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
		end
	end

	for _, house in HouseCatalog.GetAll() do
		local zone = ZoneCatalog.Get(house.RegionId)
		local slot = zone and zone.Slots[house.HouseId]
		add(errors, zone ~= nil and zone.Kind == "Income", house.HouseId .. " 未指向 Income Zone")
		add(errors, slot ~= nil and slot.Kind == "IncomeBuilding", house.HouseId .. " 缺少 IncomeBuilding Slot")
	end

	for _, spawnPoint in MonsterSpawnPointCatalog.GetAll() do
		local zone = ZoneCatalog.Get(spawnPoint.ZoneId)
		local slot = zone and zone.Slots[spawnPoint.SlotId]
		add(errors, zone ~= nil and zone.Kind == "MonsterSpawn", spawnPoint.SpawnPointId .. " 未指向 MonsterSpawn Zone")
		add(errors, slot ~= nil and slot.Kind == "MonsterSpawnPoint", spawnPoint.SpawnPointId .. " 缺少 MonsterSpawnPoint Slot")

		local maxLevel = 0
		for level in spawnPoint.MonsterKeyByLevel do
			if type(level) == "number" and level % 1 == 0 and level > maxLevel then
				maxLevel = level
			end
		end
		for level = 1, maxLevel do
			local monsterKey = spawnPoint.MonsterKeyByLevel[level]
			add(errors, monsterKey ~= nil, string.format("%s 缺少怪兽等级 %d", spawnPoint.SpawnPointId, level))
			if monsterKey then
				add(errors, MonsterCatalog.Get(monsterKey) ~= nil, spawnPoint.SpawnPointId .. " 引用了未知 MonsterKey " .. monsterKey)
			end
		end
	end

	return { Valid = #errors == 0, Errors = errors }
end

function ContentContractValidator.AssertValid(): boolean
	local result = ContentContractValidator.Validate()
	assert(result.Valid, "内容合同无效：\n" .. table.concat(result.Errors, "\n"))
	return true
end

return ContentContractValidator
