local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.Server
local HouseStateService = require(Server.HouseStateService)
local MoneyService = require(Server.MoneyService)
local MonsterSpawnPointStateService = require(Server.MonsterSpawnPointStateService)
local MonsterStateService = require(Server.MonsterStateService)
local PlayerSaveStateAdapter = require(Server.PlayerSaveStateAdapter)
local RegionStateService = require(Server.RegionStateService)
local PlayerSaveSchema = require(ReplicatedStorage.Shared.Persistence.PlayerSaveSchema)

local PlayerSaveStateAdapterSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "PlayerSaveStateAdapterSpec: " .. message)
end

function PlayerSaveStateAdapterSpec.Run(player: Player?): boolean
	local testPlayer = player or Players:GetPlayers()[1]
	assert(testPlayer, "PlayerSaveStateAdapterSpec 需要服务器中的测试玩家")

	MoneyService.Set(testPlayer, 123)
	RegionStateService.SetUnlocked(testPlayer, "R1", true)
	RegionStateService.SetLevel(testPlayer, "R1", 2)
	HouseStateService.RestoreDurable(testPlayer, "R1-H1", true, 42, 100)
	local _, destroyed = HouseStateService.Destroy(testPlayer, "R1-H1", 999)
	expect(destroyed, "测试房屋必须能进入 Destroyed")
	MonsterStateService.SetCapacity(testPlayer, 4)
	MonsterSpawnPointStateService.Restore(testPlayer, "M1-S1", true, 2, "P4")
	local monster = MonsterStateService.Create(testPlayer, "M1-S1", "P4", CFrame.new(), 100)
	expect(monster ~= nil, "测试怪兽会话状态必须创建")
	MonsterStateService.SetState(testPlayer, "M1-S1", "FightingMonster")
	MonsterStateService.SetHealth(testPlayer, "M1-S1", 1)

	local captured = PlayerSaveStateAdapter.Capture(testPlayer, 200)
	local normalized = PlayerSaveSchema.Normalize(captured)
	expect(normalized ~= nil, "快照必须符合 V1 Schema")
	expect(normalized.Houses["R1-H1"].Built, "Destroyed 房屋仍是已建资产")
	expect(normalized.Houses["R1-H1"].LifeState == nil, "不得保存房屋临时生命周期")
	expect(normalized.Monsters.SpawnPoints["M1-S1"].Health == nil, "不得保存怪兽临时血量")
	expect(normalized.Monsters.SpawnPoints["M1-S1"].State == nil, "不得保存怪兽行为状态")

	MoneyService.Set(testPlayer, 0)
	HouseStateService.RestoreDurable(testPlayer, "R1-H1", false, 0, 300)
	MonsterSpawnPointStateService.Restore(testPlayer, "M1-S1", false, 0, nil)
	PlayerSaveStateAdapter.Apply(testPlayer, normalized, 300)

	expect(MoneyService.Get(testPlayer) == 123, "金钱恢复错误")
	local restoredHouse = HouseStateService.Get(testPlayer, "R1-H1")
	expect(restoredHouse.LifeState == "Alive", "重连后已建房屋必须安全恢复 Alive")
	expect(restoredHouse.StoredMoney == 42, "未领取收入恢复错误")
	expect(restoredHouse.RespawnAt == nil, "不得恢复摧毁计时")
	expect(MonsterStateService.Get(testPlayer, "M1-S1") == nil, "不得恢复旧怪兽会话实体")
	expect(MonsterStateService.GetCapacity(testPlayer) == 4, "怪兽容量恢复错误")
	local restoredSpawnPoint = MonsterSpawnPointStateService.Get(testPlayer, "M1-S1")
	expect(restoredSpawnPoint.Built and restoredSpawnPoint.Level == 2, "出生点资产恢复错误")
	expect(restoredSpawnPoint.MonsterKey == "P4", "最新等级怪兽恢复错误")
	return true
end

return PlayerSaveStateAdapterSpec
