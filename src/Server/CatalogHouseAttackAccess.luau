local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseAttackTargetAccess = require(script.Parent.HouseAttackTargetAccess)
local HouseIncomeService = require(script.Parent.HouseIncomeService)
local HouseStateService = require(script.Parent.HouseStateService)
local RegionStateService = require(script.Parent.RegionStateService)
local HouseBoundsResolver = require(ReplicatedStorage.Shared.Building.HouseBoundsResolver)
local HouseCatalog = require(ReplicatedStorage.Shared.Building.HouseCatalog)

local CatalogHouseAttackAccess = {}

-- 输入：正式房屋状态所属的 player。
-- 输出：该玩家当前已建造且 Alive 的正式房屋范围，按 HouseId 稳定排序。
-- 副作用：无。
function CatalogHouseAttackAccess.ListAliveTargets(
	player: Player
): { HouseAttackTargetAccess.HouseTarget }
	assert(player:IsA("Player"), "player 必须是 Player")

	local targets = {}
	for _, definition in HouseCatalog.GetAll() do
		local state = HouseStateService.Get(player, definition.HouseId)
		local level = RegionStateService.GetLevel(player, definition.RegionId)
		if state.LifeState == "Alive" and level > 0 then
			local bounds = HouseBoundsResolver.Resolve(definition, level)
			table.insert(targets, {
				HouseId = definition.HouseId,
				CFrame = bounds.CFrame,
				Size = bounds.Size,
			})
		end
	end

	return targets
end

-- 输入：player、正式目录中的 houseId。
-- 输出：房屋当前仍可攻击时返回最新范围，否则返回 nil 和明确原因。
-- 副作用：无。
function CatalogHouseAttackAccess.ResolveAliveTarget(
	player: Player,
	houseId: string
): (HouseAttackTargetAccess.HouseTarget?, string?)
	local definition = HouseCatalog.Get(houseId)
	if not definition then
		return nil, "UnknownHouse"
	end

	if HouseStateService.Get(player, houseId).LifeState ~= "Alive" then
		return nil, "HouseNotAlive"
	end

	local level = RegionStateService.GetLevel(player, definition.RegionId)
	if level <= 0 then
		return nil, "RegionNotBuilt"
	end

	local bounds = HouseBoundsResolver.Resolve(definition, level)
	return {
		HouseId = houseId,
		CFrame = bounds.CFrame,
		Size = bounds.Size,
	}, nil
end

-- 输入：player、即将摧毁的正式 houseId。
-- 输出：是否成功把摧毁前尚未结算的房屋收入写回房屋状态。
-- 副作用：成功时可能增加该房屋的 StoredMoney，但不发放玩家余额。
function CatalogHouseAttackAccess.PrepareDestroy(
	player: Player,
	houseId: string
): (boolean, string?)
	local settlement = HouseIncomeService.SettleHouse(player, houseId, os.time())
	if not settlement.Accepted then
		-- 保持原 HouseAttackCommitService 对外失败原因，不泄漏收入模块内部原因。
		return false, "IncomeSettlementFailed"
	end

	return true, nil
end

-- 输入：player、已通过最新校验的正式 houseId。
-- 输出：是否首次完成 Alive -> Destroyed。
-- 副作用：调用 HouseStateService 切换房屋权威状态。
function CatalogHouseAttackAccess.Destroy(player: Player, houseId: string): boolean
	local _, changed = HouseStateService.Destroy(player, houseId)
	return changed
end

return CatalogHouseAttackAccess
