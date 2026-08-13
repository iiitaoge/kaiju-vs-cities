local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthResetRules = require(
	ReplicatedStorage.Shared.Progression.RebirthResetRules
)
local TutorialProgression = require(
	ReplicatedStorage.Shared.Tutorial.TutorialProgression
)

local Spec = {}

function Spec.Run(): boolean
	local reset = RebirthResetRules.Create(3, 123, {
		Diamond = 55,
		DailyReward = { Day = 4, NextClaimAt = 456 },
		GroupRewardClaims = { GroupJoinRewardV1 = true },
		Purchases = {
			ProcessedPurchaseIds = { Receipt_01 = true },
			PendingMonsterUpgrade = { ProductId = 123, SpawnPointId = "M1-S1" },
		},
	})
	assert(reset.Rebirth.Count == 4, "重生次数没有加一")
	assert(reset.Rebirth.RunEarnings == 0, "本轮累计收入没有归零")
	assert(reset.SavedAt == 123, "提交时间错误")
	assert(reset.Economy.Money == 0, "现金没有重置")
	assert(
		reset.Tutorial.Version == TutorialProgression.CurrentVersion,
		"重生后不应再次显示新手引导"
	)
	assert(reset.Economy.Diamond == 55, "钻石没有保留")
	assert(
		reset.DailyReward.Day == 4 and reset.DailyReward.NextClaimAt == 456,
		"七日奖励进度没有保留"
	)
	assert(reset.GroupRewardClaims.GroupJoinRewardV1, "群组奖励领取记录没有保留")
	assert(reset.Purchases.ProcessedPurchaseIds.Receipt_01, "收据幂等记录没有保留")
	assert(
		reset.Purchases.PendingMonsterUpgrade.SpawnPointId == "M1-S1",
		"付费怪兽意图没有保留"
	)
	assert(next(reset.Zones) == nil, "区域没有重置")
	assert(next(reset.Houses) == nil, "房屋没有重置")
	assert(next(reset.Monsters.SpawnPoints) == nil, "怪兽出生点没有重置")
	assert(next(reset.DefenseMonsters.SpawnPoints) == nil, "防守怪兽没有重置")
	return true
end

return Spec
