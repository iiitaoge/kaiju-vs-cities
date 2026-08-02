local PlayerRuntimeHouseAttackAccess = require(script.Parent.PlayerRuntimeHouseAttackAccess)

local AliveHouseTargetQuery = {}

export type HouseCandidate = {
	HouseId: string,
	CFrame: CFrame,
	Size: Vector3,
}

-- 输入：
--   player：拥有服务器运行时城市的防守玩家。
-- 输出：
--   该玩家当前所有 Alive 权威房屋的实际世界范围，按 HouseCatalog 稳定排序。
function AliveHouseTargetQuery.List(player: Player): { HouseCandidate }
	return PlayerRuntimeHouseAttackAccess.ListAliveTargets(player)
end

return AliveHouseTargetQuery
