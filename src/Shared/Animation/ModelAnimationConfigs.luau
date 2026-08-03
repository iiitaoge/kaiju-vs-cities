--[[
	职责：为当前所有怪兽实际等级提供统一的动画资源配置。
	输入：调用方按 MonsterKey 查表；输出：共享的不可变动画配置。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)

local animationDefinition = table.freeze({
	Animations = table.freeze({
		LeftAttack = 138906116804665,
		Eat = 84366814671336,
		RightAttack = 121743350728399,
		TailAttack = 105227212174985,
		Walk = 78047519271671,
	}),
	AttackSequence = table.freeze({
		"LeftAttack",
		"RightAttack",
		"TailAttack",
	}),
})

local configs = {}
for _, definition in MonsterCatalog.GetAll() do
	configs[definition.MonsterKey] = animationDefinition
end

return table.freeze(configs)
