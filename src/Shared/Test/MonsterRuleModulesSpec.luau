local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- 输入：无。
-- 输出：全部独立规则通过时返回 true；任一契约变化时 assert 失败。
-- 内部算法：覆盖容量边界、状态权限、伤害归零、旋转地盘、稳定选敌和包围盒距离。
function MonsterRuleModulesSpec.Run(): boolean
	expect(SoloMonsterAttackConfigs.AttackDuration == 3, "单人攻击表演时长必须为 3 秒")
	expect(
		type(SoloMonsterAttackConfigs.BoundsPartName) == "string"
			and SoloMonsterAttackConfigs.BoundsPartName ~= "",
		"单人攻击范围名称无效"
	)
	expect(
		MonsterAttackProtocol.TargetQueryRemoteName ~= MonsterAttackProtocol.CommandRemoteName,
		"目标查询和攻击命令必须使用独立 Remote"
	)
	for _, definition in MonsterCatalog.GetAll() do
		local monsterKey = definition.MonsterKey
		local attack = MonsterAttackConfigs[monsterKey]
		local expedition = MonsterExpeditionConfigs[monsterKey]
		expect(attack ~= nil and attack.StructureDamage > 0, monsterKey .. " 建筑伤害无效")
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

	return true
end

return MonsterRuleModulesSpec
