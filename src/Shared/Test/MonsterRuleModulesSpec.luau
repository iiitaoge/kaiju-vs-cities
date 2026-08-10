local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelAnimationConfigs = require(ReplicatedStorage.Shared.Animation.ModelAnimationConfigs)
local EnemyTargetSelector = require(ReplicatedStorage.Shared.Monster.EnemyTargetSelector)
local MonsterCapacityRules = require(ReplicatedStorage.Shared.Monster.MonsterCapacityRules)
local MonsterCombatGeometry = require(ReplicatedStorage.Shared.Monster.MonsterCombatGeometry)
local MonsterAttackProtocol = require(ReplicatedStorage.Shared.Monster.MonsterAttackProtocol)
local MonsterAttackConfigs = require(ReplicatedStorage.Shared.Monster.MonsterAttackConfigs)
local MonsterCatalog = require(ReplicatedStorage.Shared.Monster.MonsterCatalog)
local MonsterExpeditionConfigs = require(ReplicatedStorage.Shared.Monster.MonsterExpeditionConfigs)
local MonsterHealthRules = require(ReplicatedStorage.Shared.Monster.MonsterHealthRules)
local MonsterMovementRules = require(
	ReplicatedStorage.Shared.Monster.MonsterMovementRules
)
local SoloMonsterAttackConfigs = require(
	ReplicatedStorage.Shared.Monster.SoloMonsterAttackConfigs
)
local MonsterStateRules = require(ReplicatedStorage.Shared.Monster.MonsterStateRules)
local TerritoryPointRules = require(ReplicatedStorage.Shared.Monster.TerritoryPointRules)

local MonsterRuleModulesSpec = {}

local expectedAtomicAttackAnimationIdsByForm = {
	[1] = 124495547756102,
	[2] = 93928197656163,
	[3] = 132502964657938,
	[4] = 132502964657938,
	[5] = 126319293232039,
}

local function expect(condition: boolean, message: string)
	assert(condition, "MonsterRuleModulesSpec: " .. message)
end

local function makeBoxModel(name: string, cframe: CFrame, size: Vector3): Model
	local model = Instance.new("Model")
	model.Name = name
	local part = Instance.new("Part")
	part.Name = "Root"
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Parent = model
	model.PrimaryPart = part
	return model
end

local function faceModelAt(model: Model, targetPosition: Vector3)
	local pivot = model:GetPivot()
	local horizontalTarget = Vector3.new(targetPosition.X, pivot.Position.Y, targetPosition.Z)
	model:PivotTo(CFrame.lookAt(pivot.Position, horizontalTarget))
end

-- 输入：无。
-- 输出：全部独立规则通过时返回 true；任一契约变化时 assert 失败。
-- 内部算法：覆盖容量边界、状态权限、伤害归零、旋转地盘、稳定选敌和包围盒距离。
function MonsterRuleModulesSpec.Run(): boolean
	expect(
		SoloMonsterAttackConfigs.ShowcasePlotName == "SoloShowcasePlot",
		"固定单人演示 Plot 名称无效"
	)
	expect(
		type(SoloMonsterAttackConfigs.AttackableRegionIds) == "table"
			and #SoloMonsterAttackConfigs.AttackableRegionIds == 2
			and SoloMonsterAttackConfigs.AttackableRegionIds[1] == "R1"
			and SoloMonsterAttackConfigs.AttackableRegionIds[2] == "R2",
		"单人演示可攻击区域配置无效"
	)
	expect(
		MonsterAttackProtocol.TargetQueryRemoteName ~= MonsterAttackProtocol.CommandRemoteName,
		"目标查询和攻击命令必须使用独立 Remote"
	)
	for _, definition in MonsterCatalog.GetAll() do
		local monsterKey = definition.MonsterKey
		local animation = ModelAnimationConfigs[monsterKey]
		local attack = MonsterAttackConfigs[monsterKey]
		local expedition = MonsterExpeditionConfigs[monsterKey]
		expect(attack ~= nil and attack.StructureDamage > 0, monsterKey .. " 建筑伤害无效")
		expect(animation ~= nil, monsterKey .. " 缺少动画配置")
		expect(animation.Animations.LeftAttack == 138906116804665, monsterKey .. " 左攻击动画 ID 被改写")
		expect(animation.Animations.RightAttack == 121743350728399, monsterKey .. " 右攻击动画 ID 被改写")
		expect(animation.Animations.TailAttack == 105227212174985, monsterKey .. " 甩尾动画 ID 被改写")
		expect(
			animation.Animations.AtomicAttack
				== expectedAtomicAttackAnimationIdsByForm[definition.FormIndex],
			monsterKey .. " 激光动画 ID 与形态映射不一致"
		)
		expect(#animation.AttackSequence == 4, monsterKey .. " 缺少激光攻击轮换")
		expect(animation.AttackSequence[4] == "AtomicAttack", monsterKey .. " 激光攻击顺序错误")
		expect(#animation.MeleeAttackSequence == 3, monsterKey .. " 肉搏攻击顺序长度错误")
		expect(
			animation.MeleeAttackSequence[1] == "LeftAttack"
				and animation.MeleeAttackSequence[2] == "RightAttack"
				and animation.MeleeAttackSequence[3] == "TailAttack",
			monsterKey .. " 守卫战不得混入激光攻击"
		)
		expect(animation.AttackEffects.LeftAttack == "VFX_tail1", monsterKey .. " 左攻击特效映射错误")
		expect(animation.AttackEffects.RightAttack == "VFX_tail2", monsterKey .. " 右攻击特效映射错误")
		expect(animation.AttackEffects.TailAttack == "VFX_tail3", monsterKey .. " 甩尾特效映射错误")
		expect(animation.AttackEffects.AtomicAttack == "VFX_ATM1", monsterKey .. " 激光特效映射错误")
		expect(expedition ~= nil, monsterKey .. " 缺少正式远征配置")
		expect(expedition.RewardAmount > 0, monsterKey .. " 摧毁奖励必须为正数")
		expect(expedition.Movement.MoveSpeed == 100, monsterKey .. " 出征基础移速错误")
		expect(expedition.Movement.MaxTravelDuration == 3, monsterKey .. " 最长到达时间错误")
		expect(expedition.Movement.TimingSafetyMargin == 0.1, monsterKey .. " 移动调度余量错误")
		expect(expedition.Movement.TurnDuration == 0.2, monsterKey .. " 转向速度错误")
		expect(attack.Animation.Speed == 2, monsterKey .. " 建筑攻击动画速度错误")
		expect(expedition.RecoveryDuration >= 0, monsterKey .. " 恢复时间无效")
		expect(expedition.Combat.Damage > 0, monsterKey .. " 互殴伤害无效")
		expect(expedition.Combat.Movement.MoveSpeed == 100, monsterKey .. " 互殴接敌移速错误")
		expect(expedition.Combat.AttackInterval == 0.5, monsterKey .. " 互殴间隔错误")
		expect(expedition.Combat.Animation.Speed == 2, monsterKey .. " 互殴动画速度错误")
		expect(
			math.abs(MonsterMovementRules.ResolveWalkAnimationSpeed(
				expedition.Movement.MoveSpeed,
				expedition.Movement.WalkAnimation
			) - 2.5) <= 1e-6,
			monsterKey .. " 基础行走动画倍率错误"
		)
		expect(
			math.abs(MonsterMovementRules.ResolveDetectionRadius(
				attack.Detection.Radius,
				expedition.Movement.MoveSpeed,
				attack.Detection.MovementLookAheadSeconds
			) - 45) <= 1e-6,
			monsterKey .. " 基础高速检测半径错误"
		)
		local longDistanceSpeed = MonsterMovementRules.ResolveMoveSpeed(
			1_200,
			expedition.Movement
		)
		expect(
			expedition.Movement.TurnDuration + 1_200 / longDistanceSpeed <= 3,
			monsterKey .. " 无法在 3 秒内到达远距离目标"
		)
	end

	local addAllowed = MonsterCapacityRules.CheckAdd(1, 2)
	expect(addAllowed.Allowed, "容量未满时应允许新增")
	expect(
		MonsterCapacityRules.CheckAdd(2, 2).Reason == "CapacityReached",
		"容量已满时应拒绝新增"
	)
	expect(
		MonsterCapacityRules.CheckSet(3, 1).Allowed,
		"降低容量不应删除或拒绝已有怪兽"
	)

	expect(
		MonsterStateRules.CheckTransition("IdleAtSpawn", "Releasing").Allowed,
		"空闲怪兽应先进入释放"
	)
	expect(
		MonsterStateRules.CheckTransition("Releasing", "MovingToTarget").Allowed,
		"释放完成后应能出征"
	)
	expect(
		MonsterStateRules.CheckTransition("Releasing", "Returning").Allowed,
		"释放取消后应能回罐"
	)
	expect(
		not MonsterStateRules.CheckUpgrade("FightingMonster").Allowed,
		"战斗中的怪兽必须禁止升级"
	)
	expect(
		MonsterStateRules.CheckTransition("Defeated", "Recovering").Allowed,
		"死亡后应能进入恢复"
	)

	local damaged = MonsterHealthRules.ApplyDamage(100, 100, 35)
	expect(damaged.Succeeded and damaged.RemainingHealth == 65, "普通伤害计算错误")
	local defeated = MonsterHealthRules.ApplyDamage(20, 100, 99)
	expect(
		defeated.Defeated and defeated.RemainingHealth == 0 and defeated.DamageApplied == 20,
		"致死伤害必须截断到零"
	)

	local territory = CFrame.new(10, 0, 20) * CFrame.Angles(0, math.rad(35), 0)
	expect(
		TerritoryPointRules.Check(territory, Vector3.new(40, 10, 20), territory.Position).Allowed,
		"旋转地盘中心应有效"
	)
	local outsidePoint = territory:PointToWorldSpace(Vector3.new(30, 0, 0))
	expect(
		not TerritoryPointRules.Check(territory, Vector3.new(40, 10, 20), outsidePoint).Allowed,
		"旋转地盘外坐标应被拒绝"
	)

	local selected = EnemyTargetSelector.Select(Vector3.zero, {
		{
			TargetId = "B",
			OwnerUserId = 2,
			Position = Vector3.new(5, 0, 0),
			Active = true,
		},
		{
			TargetId = "A",
			OwnerUserId = 2,
			Position = Vector3.new(-5, 0, 0),
			Active = true,
		},
		{
			TargetId = "CloserThirdParty",
			OwnerUserId = 3,
			Position = Vector3.new(1, 0, 0),
			Active = true,
		},
	}, {
		TargetOwnerUserId = 2,
		MaxDistance = 10,
	})
	expect(selected ~= nil and selected.TargetId == "A", "选敌必须过滤玩家并稳定处理等距")
	local unboundedSelected = EnemyTargetSelector.Select(Vector3.zero, {
		{
			TargetId = "SameRegionDefender",
			OwnerUserId = 2,
			Position = Vector3.new(1_000, 0, 0),
			Active = true,
		},
	}, {
		TargetOwnerUserId = 2,
	})
	expect(
		unboundedSelected ~= nil and unboundedSelected.TargetId == "SameRegionDefender",
		"未提供距离上限时，同区域候选不应因槽位距离失效"
	)

	local attacker = makeBoxModel("Attacker", CFrame.new(0, 0, 0), Vector3.new(4, 4, 4))
	local target = makeBoxModel("Target", CFrame.new(10, 0, 0), Vector3.new(4, 4, 4))
	local gap = MonsterCombatGeometry.GetGap(attacker, target)
	expect(math.abs(gap - 6) < 1e-4, "怪兽水平包围盒距离错误")
	local pose = MonsterCombatGeometry.ResolvePose(attacker, target, 2)
	expect(typeof(pose.Position) == "Vector3", "怪兽攻击站位应返回 Vector3")
	attacker:Destroy()
	target:Destroy()

	-- 静止的大型怪兽初始侧身时，必须先转入最终朝向再求站位；否则转向会
	-- 改变长方形包围盒的水平投影，使 DesiredGap=2 在首次攻击前失效。
	local approaching = makeBoxModel(
		"Approaching",
		CFrame.new(0, 0, 50),
		Vector3.new(4, 4, 4)
	)
	local largeTarget = makeBoxModel(
		"LargeTarget",
		CFrame.lookAt(Vector3.zero, Vector3.new(1, 0, 0)),
		Vector3.new(40, 4, 10)
	)
	faceModelAt(largeTarget, approaching:GetPivot().Position)
	local mutualFacingPose = MonsterCombatGeometry.ResolvePose(approaching, largeTarget, 2)
	approaching:PivotTo(CFrame.lookAt(
		mutualFacingPose.Position,
		mutualFacingPose.LookAtPosition
	))
	local mutualFacingGap = MonsterCombatGeometry.GetGap(approaching, largeTarget)
	expect(
		math.abs(mutualFacingGap - 2) < 1e-4,
		"大型怪兽转向后的接敌距离必须保持 DesiredGap"
	)
	approaching:Destroy()
	largeTarget:Destroy()

	return true
end

return MonsterRuleModulesSpec
