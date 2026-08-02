local CatalogHouseAttackAccess = require(script.Parent.CatalogHouseAttackAccess)

local AliveHouseTargetQuery = {}

export type HouseCandidate = {
	HouseId: string,
	CFrame: CFrame,
	Size: Vector3,
}

-- 输入：
--   player：房屋逻辑状态和区域等级所属的玩家。
-- 输出：
--   该玩家当前所有 Alive 房屋的世界范围数组，顺序与 HouseCatalog.GetAll 一致。
function AliveHouseTargetQuery.List(player: Player): { HouseCandidate }
	return CatalogHouseAttackAccess.ListAliveTargets(player)
end

return AliveHouseTargetQuery
