local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSaveSchema = require(ReplicatedStorage.Shared.Persistence.PlayerSaveSchema)

local PlayerSaveSchemaSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "PlayerSaveSchemaSpec: " .. message)
end

function PlayerSaveSchemaSpec.Run(): boolean
	local default = PlayerSaveSchema.Normalize(nil)
	expect(default.Version == 1 and default.Economy.Money == 0, "默认档错误")
	expect(default.Rebirth.Count == 0, "默认重生次数必须为 0")
	expect(default.Rebirth.RunEarnings == 0, "默认本轮累计收入必须为 0")
	expect(default.Tutorial.Version == 0, "默认引导版本必须为 0")

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
	expect(migrated.Rebirth.Count == 0, "旧存档重生次数应默认为 0")
	expect(migrated.Tutorial.Version == 0, "旧存档引导版本应默认为 0")
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

	local invalid, reason = PlayerSaveSchema.Normalize({ Version = 99 })
	expect(invalid == nil and reason == "FutureSaveVersion", "未来版本必须拒绝")
	local corrupt, corruptReason = PlayerSaveSchema.Normalize("bad")
	expect(corrupt == nil and corruptReason == "CorruptSave", "损坏档必须拒绝")
	return true
end

return PlayerSaveSchemaSpec
