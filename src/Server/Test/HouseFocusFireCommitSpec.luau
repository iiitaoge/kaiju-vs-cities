local HouseAttackCommitter = require(script.Parent.Parent.HouseAttackCommitter)
local HouseHealthStateService = require(script.Parent.Parent.HouseHealthStateService)
local HouseTargetReservationService = require(
	script.Parent.Parent.HouseTargetReservationService
)
local MoneyService = require(script.Parent.Parent.MoneyService)

local HouseFocusFireCommitSpec = {}

local HOUSE_ID = "Spec-FocusFireHouse"
local MAX_HEALTH = 100
local DAMAGE = 60
local REWARD = 7

local function expect(condition: boolean, message: string)
	assert(condition, "HouseFocusFireCommitSpec: " .. message)
end

local function makeMonster(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.Size = Vector3.new(4, 4, 4)
	root.CFrame = CFrame.new(0, 2, 0)
	root.Parent = model
	model.PrimaryPart = root
	model.Parent = workspace
	return model
end

-- 输入：一个在线 Player，兼作测试房屋状态拥有者和奖励接收者。
-- 输出：两个凭证可同时命中、仅最后一击摧毁并奖励、凭证全部清空时返回 true。
-- 内部算法：同代获取两张凭证 → 第一击保留 40 HP → 第二击归零并提交一次 Destroy。
function HouseFocusFireCommitSpec.Run(player: Player): boolean
	local monsterA = makeMonster("FocusFireA")
	local monsterB = makeMonster("FocusFireB")
	local initialBalance = MoneyService.Get(player)
	local destroyed = false
	local prepareCount = 0
	local destroyCount = 0
	HouseHealthStateService.Clear(player)
	local initialHealth = HouseHealthStateService.ResetFull(player, HOUSE_ID, 1, MAX_HEALTH)

	local access = {}
	function access.ResolveAliveTarget(_player: Player, houseId: string)
		if destroyed or houseId ~= HOUSE_ID then
			return nil, "HouseNotAlive"
		end
		local health = assert(HouseHealthStateService.Get(player, HOUSE_ID))
		return {
			HouseId = HOUSE_ID,
			RegionId = "Spec",
			CFrame = CFrame.new(0, 2, 0),
			Size = Vector3.new(4, 4, 4),
			HealthGeneration = health.Generation,
			CurrentHealth = health.CurrentHealth,
			MaxHealth = health.MaxHealth,
		}, nil
	end
	function access.ListAliveTargets(_player: Player)
		local target = access.ResolveAliveTarget(player, HOUSE_ID)
		return if target then { target } else {}
	end
	function access.ApplyDamage(
		_player: Player,
		houseId: string,
		expectedGeneration: number,
		damage: number
	)
		return HouseHealthStateService.ApplyDamage(
			player,
			houseId,
			expectedGeneration,
			damage
		)
	end
	function access.RollbackDamage(
		_player: Player,
		houseId: string,
		expectedGeneration: number,
		previousHealth: number
	)
		return HouseHealthStateService.RollbackDamage(
			player,
			houseId,
			expectedGeneration,
			previousHealth
		)
	end
	function access.PrepareDestroy(_player: Player, _houseId: string)
		prepareCount += 1
		return true, nil
	end
	function access.Destroy(_player: Player, _houseId: string)
		if destroyed then
			return false, "HouseNotAlive"
		end
		destroyed = true
		destroyCount += 1
		return true, nil
	end

	local ok, errorMessage = xpcall(function()
		local reservationA = assert(HouseTargetReservationService.TryAcquire(
			player,
			HOUSE_ID,
			monsterA,
			initialHealth.Generation
		))
		local reservationB = assert(HouseTargetReservationService.TryAcquire(
			player,
			HOUSE_ID,
			monsterB,
			initialHealth.Generation
		))
		expect(HouseTargetReservationService.GetActiveCount(player, HOUSE_ID) == 2, "未允许集火")

		local first = HouseAttackCommitter.Commit(reservationA, access, {
			MaxGap = 0,
			Damage = DAMAGE,
			RewardAmount = REWARD,
			RewardPlayer = player,
		})
		expect(first.Succeeded and not first.Destroyed, "第一击不应摧毁房屋")
		expect(first.RemainingHealth == 40 and first.DamageApplied == 60, "第一击血量错误")
		expect(first.RewardGranted == 0 and MoneyService.Get(player) == initialBalance, "非致命命中奖励错误")
		expect(HouseTargetReservationService.GetActiveCount(player, HOUSE_ID) == 1, "第一张凭证未单独释放")

		local second = HouseAttackCommitter.Commit(reservationB, access, {
			MaxGap = 0,
			Damage = DAMAGE,
			RewardAmount = REWARD,
			RewardPlayer = player,
		})
		expect(second.Succeeded and second.Destroyed, "第二击必须摧毁房屋")
		expect(second.DamageApplied == 40 and second.RemainingHealth == 0, "致命伤害必须截断")
		expect(second.RewardGranted == REWARD, "最后一击奖励错误")
		expect(MoneyService.Get(player) == initialBalance + REWARD, "奖励余额错误")
		expect(prepareCount == 1 and destroyCount == 1, "生命周期只能提交一次")
		expect(HouseTargetReservationService.GetActiveCount(player, HOUSE_ID) == 0, "致命后仍残留凭证")
	end, debug.traceback)

	monsterA:Destroy()
	monsterB:Destroy()
	HouseTargetReservationService.InvalidateHouse(player, HOUSE_ID)
	HouseHealthStateService.Clear(player)
	if MoneyService.Get(player) > initialBalance then
		MoneyService.TrySpend(player, MoneyService.Get(player) - initialBalance)
	end
	if not ok then
		error(errorMessage, 0)
	end
	return true
end

return HouseFocusFireCommitSpec
