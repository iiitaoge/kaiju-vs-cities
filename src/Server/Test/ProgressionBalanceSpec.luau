--[[
	职责：锁定 R1～R6 首轮约 25 分钟、30 级上限和怪兽/建筑匹配战斗节奏。
	输入：正式经济、Boost、耐久、怪兽与槽位配置。
	输出：纯模拟里程碑；断言失败表示配置已经偏离目标，不创建玩家或 Instance。
	内部算法：按新区升至 Level 5、依次购买三段 Boost，并穿插四槽和主怪兽升级。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyMath = require(script.Parent.Parent.EconomyMath)
local IncomeZoneBoostConfigs = require(script.Parent.Parent.IncomeZoneBoostConfigs)
local RegionEconomyConfigs = require(script.Parent.Parent.RegionEconomyConfigs)
local RegionUpgradeConfigs = require(script.Parent.Parent.RegionUpgradeConfigs)
local MonsterAttackConfigs = require(ReplicatedStorage.Shared.Monster.MonsterAttackConfigs)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local MonsterExpeditionConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionConfigs
)
local MonsterSpawnPointCatalog = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog
)
local MonsterSpawnPointEconomyConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterSpawnPointEconomyConfigs
)
local StructureDurabilityConfigs = require(
	ReplicatedStorage.Shared.Building.StructureDurabilityConfigs
)

local Spec = {}

local REGION_IDS = { "R1", "R2", "R3", "R4", "R5", "R6" }
local SLOT_AFTER_REGION = {
	R1 = "M1-S1",
	R3 = "M1-S2",
	R4 = "M1-S3",
	R5 = "M1-S4",
}
local MONSTER_TARGET_AFTER_REGION = {
	R1 = 5,
	R2 = 10,
	R3 = 15,
	R4 = 20,
	R5 = 25,
}

local function simulate()
	local elapsed = 0
	local cash = 0
	local levels = {}
	local incomeMultipliers = {}
	local monsterLevel = 0
	local milestones = {}
	for _, regionId in ipairs(REGION_IDS) do
		levels[regionId] = 0
		incomeMultipliers[regionId] = 1
	end

	local function incomePerSecond(): number
		local total = 0
		for _, regionId in ipairs(REGION_IDS) do
			total += EconomyMath.GetRegionIncomePerSecond(
				RegionEconomyConfigs[regionId],
				levels[regionId],
				incomeMultipliers[regionId]
			)
		end
		return total
	end

	local function spend(cost: number)
		if cash < cost then
			local rate = incomePerSecond()
			assert(rate > 0, "没有收入时无法等待购买")
			elapsed += (cost - cash) / rate
			cash = cost
		end
		cash -= cost
	end

	local function upgradeMonsterTo(targetLevel: number)
		local economy = MonsterSpawnPointEconomyConfigs["M1-S1"]
		for level = math.max(2, monsterLevel + 1), targetLevel do
			spend(assert(economy.UpgradeCostByTargetLevel[level]))
		end
		monsterLevel = math.max(monsterLevel, targetLevel)
	end

	for _, regionId in ipairs(REGION_IDS) do
		local economy = RegionEconomyConfigs[regionId]
		if regionId ~= "R1" and regionId ~= "R2" then
			spend(economy.UnlockCost)
			milestones[regionId .. "Unlock"] = elapsed
		end
		spend(economy.PurchaseCost)
		levels[regionId] = 1
		milestones[regionId .. "Build"] = elapsed

		for targetLevel = 2, 5 do
			spend(EconomyMath.GetUpgradeCost(economy, targetLevel - 1))
			levels[regionId] = targetLevel
			local transactionIndex = targetLevel - 1
			if transactionIndex <= 3 then
				local transaction = IncomeZoneBoostConfigs[regionId].Transactions[transactionIndex]
				spend(transaction.Cost)
				if transaction.Kind == "Income" then
					incomeMultipliers[regionId] *= transaction.Factor
				end
			end
		end

		local spawnPointId = SLOT_AFTER_REGION[regionId]
		if spawnPointId then
			spend(MonsterSpawnPointEconomyConfigs[spawnPointId].BuildCost)
			monsterLevel = math.max(monsterLevel, 1)
		end
		local monsterTarget = MONSTER_TARGET_AFTER_REGION[regionId]
		if monsterTarget then
			upgradeMonsterTo(monsterTarget)
		end
	end

	return milestones
end

function Spec.Run(): boolean
	for _, regionId in ipairs(REGION_IDS) do
		assert(RegionUpgradeConfigs[regionId].Levels[30], regionId .. " 没有 30 级")
		assert(not RegionUpgradeConfigs[regionId].Levels[31], regionId .. " 超过 30 级")
		assert(StructureDurabilityConfigs.GetMaxHealth(regionId, 30), regionId .. " 缺少 30 级生命")
		for currentLevel = 1, 29 do
			local cost = EconomyMath.GetUpgradeCost(RegionEconomyConfigs[regionId], currentLevel)
			assert(cost % 1 == 0, string.format("%s Level %d 升级价格不是整数", regionId, currentLevel))
		end
	end

	local milestones = simulate()
	assert(milestones.R2Build >= 60 and milestones.R2Build <= 240, "R2 建造时间偏离前期目标")
	assert(milestones.R3Build >= 240 and milestones.R3Build <= 540, "R3 建造时间偏离目标")
	assert(milestones.R4Build >= 480 and milestones.R4Build <= 840, "R4 建造时间偏离目标")
	assert(milestones.R5Build >= 900 and milestones.R5Build <= 1_260, "R5 建造时间偏离目标")
	assert(milestones.R6Unlock >= 1_380 and milestones.R6Unlock <= 1_800, "R6 解锁不在约 25 分钟窗口")

	local matchedMonsterLevels = { R1 = 1, R2 = 5, R3 = 10, R4 = 15, R5 = 20, R6 = 25 }
	for _, regionId in ipairs(REGION_IDS) do
		local monsterLevel = matchedMonsterLevels[regionId]
		local monsterKey = assert(MonsterSpawnPointCatalog.GetMonsterKey("M1-S1", monsterLevel))
		local damage = MonsterAttackConfigs[monsterKey].StructureDamage
		local health = assert(StructureDurabilityConfigs.GetMaxHealth(regionId, if regionId == "R1" then 1 else 5))
		local hits = math.ceil(health / damage)
		assert(hits >= 4 and hits <= 12, string.format("%s 匹配战斗命中数异常：%d", regionId, hits))
	end

	for _, level in { 1, 30, 50, 75 } do
		local monsterKey = assert(MonsterSpawnPointCatalog.GetMonsterKey("M1-S1", level))
		local health = assert(MonsterCatalog.Get(monsterKey)).MaxHealth
		local damage = MonsterExpeditionConfigs[monsterKey].Combat.Damage
		local hits = math.ceil(health / damage)
		assert(hits >= 9 and hits <= 11, string.format("怪兽 Level %d 互殴节奏异常", level))
	end

	local upgradeCosts = MonsterSpawnPointEconomyConfigs["M1-S1"].UpgradeCostByTargetLevel
	for _, level in { 1, 25, 50, 74 } do
		local monsterKey = assert(MonsterSpawnPointCatalog.GetMonsterKey("M1-S1", level))
		local ratio = MonsterExpeditionConfigs[monsterKey].RewardAmount / assert(upgradeCosts[level + 1])
		assert(ratio >= 0.18 and ratio <= 0.22, string.format("怪兽 Level %d 奖励/升级比异常", level))
	end
	return true
end

return Spec
