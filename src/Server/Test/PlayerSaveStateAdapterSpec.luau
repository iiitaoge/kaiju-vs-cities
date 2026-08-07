local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.Server
local HouseStateService = require(Server.HouseStateService)
local DefenseMonsterSpawnPointStateService = require(Server.DefenseMonsterSpawnPointStateService)
local DiamondService = require(Server.DiamondService)
local MoneyService = require(Server.MoneyService)
local MonsterSpawnPointStateService = require(Server.MonsterSpawnPointStateService)
local MonsterStateService = require(Server.MonsterStateService)
local PlayerSaveStateAdapter = require(Server.PlayerSaveStateAdapter)
local RebirthStateService = require(Server.RebirthStateService)
local RegionStateService = require(Server.RegionStateService)
local SevenDayRewardStateService = require(Server.SevenDayRewardStateService)
local TutorialProgressStateService = require(Server.TutorialProgressStateService)
local PlayerSaveSchema = require(ReplicatedStorage.Shared.Persistence.PlayerSaveSchema)
local MonsterSpawnPointCatalog = require(ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog)
local TutorialProgression = require(
	ReplicatedStorage.Shared.Tutorial.TutorialProgression
)

local PlayerSaveStateAdapterSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "PlayerSaveStateAdapterSpec: " .. message)
end

function PlayerSaveStateAdapterSpec.Run(player: Player?): boolean
	local testPlayer = player or Players:GetPlayers()[1]
	assert(testPlayer, "PlayerSaveStateAdapterSpec 需要服务器中的测试玩家")

	MoneyService.Set(testPlayer, 123)
	DiamondService.Set(testPlayer, 77)
	SevenDayRewardStateService.Set(testPlayer, 3, 123456)
	RebirthStateService.Restore(testPlayer, 3, 4567)
	TutorialProgressStateService.Restore(testPlayer, TutorialProgression.CurrentVersion)
	RegionStateService.SetUnlocked(testPlayer, "R1", true)
	RegionStateService.SetLevel(testPlayer, "R1", 2)
	RegionStateService.SetIncomeMultiplier(testPlayer, "R1", 2)
	RegionStateService.SetHealthMultiplier(testPlayer, "R1", 2)
	RegionStateService.SetBoostPurchased(testPlayer, "R1", true)
	RegionStateService.SetAutoIncome(testPlayer, "R1", true)
	HouseStateService.RestoreDurable(testPlayer, "R1-H1", true, 42, 100)
	local _, destroyed = HouseStateService.Destroy(testPlayer, "R1-H1", 999)
	expect(destroyed, "测试房屋必须能进入 Destroyed")
	MonsterStateService.SetCapacity(testPlayer, 4)
	local levelTwoMonsterKey = assert(MonsterSpawnPointCatalog.GetMonsterKey("M1-S1", 2))
	MonsterSpawnPointStateService.Restore(testPlayer, "M1-S1", true, 2, levelTwoMonsterKey)
	local monster = MonsterStateService.Create(testPlayer, "M1-S1", levelTwoMonsterKey, CFrame.new(), 100)
	expect(monster ~= nil, "测试怪兽会话状态必须创建")
	MonsterStateService.SetState(testPlayer, "M1-S1", "FightingMonster")
	MonsterStateService.SetHealth(testPlayer, "M1-S1", 1)

	local captured = PlayerSaveStateAdapter.Capture(testPlayer, 200)
	local normalized = PlayerSaveSchema.Normalize(captured)
	expect(normalized ~= nil, "快照必须符合 V1 Schema")
	expect(normalized.Rebirth.Count == 3, "重生次数没有进入存档")
	expect(normalized.Economy.Diamond == 77, "钻石没有进入存档")
	expect(
		normalized.DailyReward.Day == 3
			and normalized.DailyReward.NextClaimAt == 123456,
		"七日奖励状态没有进入存档"
	)
	expect(normalized.Rebirth.RunEarnings == 4567, "本轮累计收入没有进入存档")
	expect(
		normalized.Tutorial.Version == TutorialProgression.CurrentVersion,
		"引导完成版本没有进入存档"
	)
	expect(normalized.Houses["R1-H1"].Built, "Destroyed 房屋仍是已建资产")
	expect(normalized.Houses["R1-H1"].LifeState == nil, "不得保存房屋临时生命周期")
	expect(normalized.Monsters.SpawnPoints["M1-S1"].Health == nil, "不得保存怪兽临时血量")
	expect(normalized.Monsters.SpawnPoints["M1-S1"].State == nil, "不得保存怪兽行为状态")
	expect(normalized.Zones.R1.HealthMultiplier == 2, "生命倍率没有进入存档")
	expect(normalized.Zones.R1.BoostPurchased, "Boost 状态没有进入存档")

	MoneyService.Set(testPlayer, 0)
	DiamondService.Set(testPlayer, 0)
	SevenDayRewardStateService.Set(testPlayer, 1, 0)
	RebirthStateService.Restore(testPlayer, 0, 0)
	TutorialProgressStateService.Restore(testPlayer, 0)
	HouseStateService.RestoreDurable(testPlayer, "R1-H1", false, 0, 300)
	MonsterSpawnPointStateService.Restore(testPlayer, "M1-S1", false, 0, nil)
	PlayerSaveStateAdapter.Apply(testPlayer, normalized, 300)

	expect(MoneyService.Get(testPlayer) == 123, "金钱恢复错误")
	expect(DiamondService.Get(testPlayer) == 77, "钻石恢复错误")
	local restoredDailyReward = SevenDayRewardStateService.Get(testPlayer)
	expect(
		restoredDailyReward.Day == 3
			and restoredDailyReward.NextClaimAt == 123456,
		"七日奖励状态恢复错误"
	)
	local restoredRebirth = RebirthStateService.Get(testPlayer)
	expect(restoredRebirth.Count == 3, "重生次数恢复错误")
	expect(restoredRebirth.RunEarnings == 4567, "本轮累计收入恢复错误")
	expect(
		TutorialProgressStateService.Get(testPlayer) == TutorialProgression.CurrentVersion,
		"引导完成版本恢复错误"
	)
	expect(RegionStateService.GetIncomeMultiplier(testPlayer, "R1") == 2, "收入倍率恢复错误")
	expect(RegionStateService.GetHealthMultiplier(testPlayer, "R1") == 2, "生命倍率恢复错误")
	expect(RegionStateService.GetBoostPurchased(testPlayer, "R1"), "Boost 状态恢复错误")
	expect(RegionStateService.GetAutoIncome(testPlayer, "R1"), "自动收入状态恢复错误")
	local restoredHouse = HouseStateService.Get(testPlayer, "R1-H1")
	expect(restoredHouse.LifeState == "Alive", "重连后已建房屋必须安全恢复 Alive")
	expect(restoredHouse.StoredMoney == 42, "未领取收入恢复错误")
	expect(restoredHouse.RespawnAt == nil, "不得恢复摧毁计时")
	expect(MonsterStateService.Get(testPlayer, "M1-S1") == nil, "不得恢复旧怪兽会话实体")
	expect(MonsterStateService.GetCapacity(testPlayer) == 4, "怪兽容量恢复错误")
	local restoredSpawnPoint = MonsterSpawnPointStateService.Get(testPlayer, "M1-S1")
	expect(restoredSpawnPoint.Built and restoredSpawnPoint.Level == 2, "出生点资产恢复错误")
	expect(restoredSpawnPoint.MonsterKey == levelTwoMonsterKey, "最新等级怪兽恢复错误")
	local restoredDefense = DefenseMonsterSpawnPointStateService.Get(testPlayer, "DM-R1")
	expect(not restoredDefense.Built and restoredDefense.Level == 0, "已解锁区域不得自动建造防守怪兽")
	return true
end

return PlayerSaveStateAdapterSpec
