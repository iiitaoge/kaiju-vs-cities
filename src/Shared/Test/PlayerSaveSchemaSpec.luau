local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSaveSchema = require(ReplicatedStorage.Shared.Persistence.PlayerSaveSchema)

local PlayerSaveSchemaSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "PlayerSaveSchemaSpec: " .. message)
end

function PlayerSaveSchemaSpec.Run(): boolean
	local default = PlayerSaveSchema.Normalize(nil)
	expect(
		default.Version == 1
			and default.Economy.Money == 0
			and default.Economy.Diamond == 0,
		"默认经济档错误"
	)
	expect(
		default.DailyReward.Day == 1 and default.DailyReward.NextClaimAt == 0,
		"默认七日奖励状态错误"
	)
	expect(next(default.GroupRewardClaims) == nil, "默认群组奖励领取记录必须为空")
	expect(default.Rebirth.Count == 0, "默认重生次数必须为 0")
	expect(default.Rebirth.RunEarnings == 0, "默认本轮累计收入必须为 0")
	expect(default.Tutorial.Version == 0, "默认引导版本必须为 0")
	expect(next(default.Tasks) == nil, "默认任务状态必须为空")
	expect(next(default.DefenseMonsters.SpawnPoints) == nil, "默认防守怪兽资产必须为空")

	local migrated = PlayerSaveSchema.Normalize({
		Money = 75,
		MonsterCapacity = 4,
		Zones = { R1 = { Unlocked = true, Level = 2 } },
		Houses = { ["R1-H1"] = { Built = true, StoredMoney = 9, LifeState = "Destroyed" } },
		MonsterSpawnPoints = {
			["M1-S1"] = {
				Built = true,
				Level = 1,
				MonsterKey = "Godzilla-L001",
				Health = 1,
				State = "FightingMonster",
			},
		},
	})
	expect(migrated.Version == 1 and migrated.Economy.Money == 75, "V0 金钱迁移错误")
	expect(migrated.Economy.Diamond == 0, "旧存档钻石默认值错误")
	expect(
		migrated.DailyReward.Day == 1 and migrated.DailyReward.NextClaimAt == 0,
		"旧存档七日奖励默认值错误"
	)
	expect(migrated.Rebirth.Count == 0, "旧存档重生次数应默认为 0")
	expect(migrated.Tutorial.Version == 0, "旧存档引导版本应默认为 0")
	expect(next(migrated.Tasks) == nil, "旧存档任务状态应默认为空")
	expect(migrated.Monsters.Capacity == 4, "V0 容量迁移错误")
	expect(migrated.Houses["R1-H1"].Built, "房屋建造状态迁移错误")
	expect(migrated.Houses["R1-H1"].LifeState == nil, "瞬时房屋状态不得进入 V1")
	expect(migrated.Zones.R1.HealthMultiplier == 1, "旧存档生命倍率默认值错误")
	expect(not migrated.Zones.R1.BoostPurchased, "旧存档不应默认购买 Boost")
	expect(migrated.Monsters.SpawnPoints["M1-S1"].Health == nil, "瞬时怪兽血量不得进入 V1")
	expect(migrated.Monsters.SpawnPoints["M1-S1"].State == nil, "瞬时怪兽状态不得进入 V1")

	local rebirth = PlayerSaveSchema.Normalize({
		Version = 1,
		Rebirth = { Count = 3, RunEarnings = 1250 },
	})
	expect(rebirth.Rebirth.Count == 3, "重生次数规范化错误")
	expect(rebirth.Rebirth.RunEarnings == 1250, "本轮累计收入规范化错误")

	local invalidRebirth = PlayerSaveSchema.Normalize({
		Version = 1,
		Rebirth = { Count = -1, RunEarnings = -1 },
	})
	expect(invalidRebirth.Rebirth.Count == 0, "非法重生次数必须回退为 0")
	expect(invalidRebirth.Rebirth.RunEarnings == 0, "非法本轮收入必须回退为 0")

	local tutorial = PlayerSaveSchema.Normalize({
		Version = 1,
		Tutorial = { Version = 1 },
	})
	expect(tutorial.Tutorial.Version == 1, "引导完成版本规范化错误")
	local invalidTutorial = PlayerSaveSchema.Normalize({
		Version = 1,
		Tutorial = { Version = -1 },
	})
	expect(invalidTutorial.Tutorial.Version == 0, "非法引导版本必须回退为 0")

	local rewards = PlayerSaveSchema.Normalize({
		Version = 1,
		Economy = { Diamond = 42 },
		DailyReward = { Day = 3, NextClaimAt = 123456 },
		GroupRewardClaims = {
			GroupJoinRewardV1 = true,
			["bad key"] = true,
			NotClaimed = false,
		},
	})
	expect(rewards.Economy.Diamond == 42, "钻石规范化错误")
	expect(
		rewards.DailyReward.Day == 3
			and rewards.DailyReward.NextClaimAt == 123456,
		"七日奖励状态规范化错误"
	)
	expect(
		rewards.GroupRewardClaims.GroupJoinRewardV1
		and rewards.GroupRewardClaims["bad key"] == nil
		and rewards.GroupRewardClaims.NotClaimed == nil,
		"群组奖励领取记录规范化错误"
	)
	local tasks = PlayerSaveSchema.Normalize({
		Version = 1,
		Tasks = {
			TaskA = {
				Completed = false,
				Progress = {
					Earn = { Kind = "Counter", Current = 25, Completed = false },
					Bad = { Kind = "Level", Current = -1, Completed = true },
				},
			},
			["bad key"] = { Completed = true },
		},
	})
	expect(tasks.Tasks.TaskA ~= nil, "任务状态规范化错误")
	expect(
		tasks.Tasks.TaskA.Progress.Earn.Current == 25
			and tasks.Tasks.TaskA.Progress.Bad.Current == 0
			and tasks.Tasks["bad key"] == nil,
		"任务进度数值或非法键规范化错误"
	)
	local completed = PlayerSaveSchema.Normalize({
		Version = 1,
		DailyReward = { Day = 99, NextClaimAt = 123456 },
	})
	expect(
		completed.DailyReward.Day == 8 and completed.DailyReward.NextClaimAt == 0,
		"七日奖励完成状态规范化错误"
	)

	local invalid, reason = PlayerSaveSchema.Normalize({ Version = 99 })
	expect(invalid == nil and reason == "FutureSaveVersion", "未来版本必须拒绝")
	local corrupt, corruptReason = PlayerSaveSchema.Normalize("bad")
	expect(corrupt == nil and corruptReason == "CorruptSave", "损坏档必须拒绝")
	return true
end

return PlayerSaveSchemaSpec
