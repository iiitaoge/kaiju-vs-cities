local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseAttackTargetAccess = require(script.Parent.Parent.HouseAttackTargetAccess)
local HouseStateService = require(script.Parent.Parent.HouseStateService)
local TestHouseCatalog = require(ReplicatedStorage.Shared.Test.MonsterAttackTestHouseCatalog)

local MonsterAttackTestHouseAccess = {}

-- 输入：加入测试的 player。
-- 输出：本次首次切换为 Alive 的测试房屋数量。
-- 副作用：为该玩家初始化测试房屋状态；不登记正式区域，也不生成被动收入。
function MonsterAttackTestHouseAccess.InitializePlayer(player: Player): number
	local builtCount = 0
	for _, definition in TestHouseCatalog.GetAll() do
		local _, changed = HouseStateService.Build(player, definition.HouseId)
		if changed then
			builtCount += 1
		end
	end
	return builtCount
end

-- 输入：测试房屋状态所属的 player。
-- 输出：该玩家所有 Alive 测试房屋的世界范围，按 HouseId 稳定排序。
-- 副作用：无。
function MonsterAttackTestHouseAccess.ListAliveTargets(
	player: Player
): { HouseAttackTargetAccess.HouseTarget }
	local targets = {}
	for _, definition in TestHouseCatalog.GetAll() do
		if HouseStateService.Get(player, definition.HouseId).LifeState == "Alive" then
			table.insert(targets, {
				HouseId = definition.HouseId,
				CFrame = definition.CFrame,
				Size = definition.Size,
			})
		end
	end
	return targets
end

-- 输入：player、测试 houseId。
-- 输出：房屋当前仍为 Alive 时返回最新测试范围，否则返回原因。
-- 副作用：无。
function MonsterAttackTestHouseAccess.ResolveAliveTarget(
	player: Player,
	houseId: string
): (HouseAttackTargetAccess.HouseTarget?, string?)
	local definition = TestHouseCatalog.Get(houseId)
	if not definition then
		return nil, "UnknownHouse"
	end
	if HouseStateService.Get(player, houseId).LifeState ~= "Alive" then
		return nil, "HouseNotAlive"
	end

	return {
		HouseId = houseId,
		CFrame = definition.CFrame,
		Size = definition.Size,
	}, nil
end

-- 输入：player、即将摧毁的测试 houseId。
-- 输出：始终返回成功；测试房屋没有需要结算的被动收入。
-- 副作用：无。
function MonsterAttackTestHouseAccess.PrepareDestroy(
	_player: Player,
	_houseId: string
): (boolean, string?)
	return true, nil
end

-- 输入：player、已通过最新校验的测试 houseId。
-- 输出：是否首次完成 Alive -> Destroyed。
-- 副作用：只切换该玩家的测试房屋状态。
function MonsterAttackTestHouseAccess.Destroy(player: Player, houseId: string): boolean
	local _, changed = HouseStateService.Destroy(player, houseId)
	return changed
end

return MonsterAttackTestHouseAccess
