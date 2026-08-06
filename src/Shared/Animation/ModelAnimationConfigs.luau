--[[
	职责：为当前所有怪兽实际等级提供统一的动画资源配置。
	输入：调用方按 MonsterKey 查表；输出：共享的不可变动画配置。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)

-- 每个形态使用自己发布的激光动画，避免不同骨骼层级丢失嘴部轨道。
local atomicAttackAnimationIdsByForm = table.freeze({
	[1] = 124495547756102,
	[2] = 93928197656163,
	[3] = 132502964657938,
	[4] = 132502964657938,
	[5] = 126319293232039,
})

local baseAnimations = {
	LeftAttack = 138906116804665,
	Eat = 84366814671336,
	RightAttack = 121743350728399,
	TailAttack = 105227212174985,
	Walk = 78047519271671,
}

local attackEffects = table.freeze({
	LeftAttack = "VFX_tail1",
	RightAttack = "VFX_tail2",
	TailAttack = "VFX_tail3",
	AtomicAttack = "VFX_ATM1",
})

local meleeAttackSequence = table.freeze({
	"LeftAttack",
	"RightAttack",
	"TailAttack",
})

local function makeAnimationDefinition(formIndex: number)
	local animations = table.clone(baseAnimations)
	local attackSequence = table.clone(meleeAttackSequence)
	local atomicAttackAnimationId = atomicAttackAnimationIdsByForm[formIndex]
	if atomicAttackAnimationId ~= nil then
		animations.AtomicAttack = atomicAttackAnimationId
	end

	if atomicAttackAnimationId ~= nil then
		table.insert(attackSequence, "AtomicAttack")
	end

	return table.freeze({
		Animations = table.freeze(animations),
		AttackSequence = table.freeze(attackSequence),
		MeleeAttackSequence = meleeAttackSequence,
		AttackEffects = attackEffects,
	})
end

local configs = {}
for _, definition in MonsterCatalog.GetAll() do
	configs[definition.MonsterKey] = makeAnimationDefinition(definition.FormIndex)
end

return table.freeze(configs)
