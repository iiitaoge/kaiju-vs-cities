local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthResetRules = require(
	ReplicatedStorage.Shared.Progression.RebirthResetRules
)

local Spec = {}

function Spec.Run(): boolean
	local reset = RebirthResetRules.Create(3, 123)
	assert(reset.Rebirth.Count == 4, "重生次数没有加一")
	assert(reset.Rebirth.RunEarnings == 0, "本轮累计收入没有归零")
	assert(reset.SavedAt == 123, "提交时间错误")
	assert(reset.Economy.Money == 0, "现金没有重置")
	assert(next(reset.Zones) == nil, "区域没有重置")
	assert(next(reset.Houses) == nil, "房屋没有重置")
	assert(next(reset.Monsters.SpawnPoints) == nil, "怪兽出生点没有重置")
	assert(next(reset.DefenseMonsters.SpawnPoints) == nil, "防守怪兽没有重置")
	return true
end

return Spec
