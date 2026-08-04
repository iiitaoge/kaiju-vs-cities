--[[
	职责：按防守玩家和收入区域查询当前位于区域 Bounds 内的敌方怪兽数量。

	输入：Create 注入在线玩家、玩家怪兽和防守方地盘快照查询；Count 接收防守玩家与 RegionId。
	输出：区域内敌方怪兽数量；IsOccupied 返回数量是否大于零。
	内部算法：筛选目标 RegionId 的全部 Bounds，再按怪兽 Pivot 的 X/Z 坐标逐一做旋转包围盒判定；
		同一只怪兽命中多个 Bounds 也只计数一次，防守玩家自己的怪兽不计入。

	不负责：不跟踪进入/离开事件，不修改怪兽、区域或房屋状态，不调度重建。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TerritoryPointRules = require(
	ReplicatedStorage.Shared.Monster.TerritoryPointRules
)

local PlayerRegionMonsterOccupancyQuery = {}

export type Territory = {
	ZoneId: string,
	CFrame: CFrame,
	Size: Vector3,
}

export type Bounds = {
	CFrame: CFrame,
	Size: Vector3,
}

export type MonsterRecord = {
	Model: Model?,
}

export type CreateOptions = {
	GetPlayers: () -> { Player },
	ListTerritories: (Player) -> { Territory },
	ListMonsters: (Player) -> { MonsterRecord },
}

export type Access = {
	Count: (Player, string) -> number,
	IsOccupied: (Player, string) -> boolean,
}

-- 输入：同一区域的 Bounds 和每只候选敌方怪兽的 Pivot 位置。
-- 输出：至少命中一个 Bounds 的位置数量；同一位置命中重叠 Bounds 只计数一次。
-- 内部算法：复用 TerritoryPointRules 的旋转包围盒 X/Z 判定。
function PlayerRegionMonsterOccupancyQuery.CountPositions(
	bounds: { Bounds },
	positions: { Vector3 }
): number
	local occupiedCount = 0
	for _, position in positions do
		for _, territory in bounds do
			if TerritoryPointRules.Check(
				territory.CFrame,
				territory.Size,
				position
			).Allowed then
				occupiedCount += 1
				break
			end
		end
	end
	return occupiedCount
end

function PlayerRegionMonsterOccupancyQuery.Create(options: CreateOptions): Access
	assert(type(options) == "table", "options 必须是 table")
	assert(type(options.GetPlayers) == "function", "GetPlayers 必须是 function")
	assert(
		type(options.ListTerritories) == "function",
		"ListTerritories 必须是 function"
	)
	assert(type(options.ListMonsters) == "function", "ListMonsters 必须是 function")

	local function count(defender: Player, regionId: string): number
		assert(
			typeof(defender) == "Instance" and defender:IsA("Player"),
			"defender 必须是 Player"
		)
		assert(type(regionId) == "string" and regionId ~= "", "regionId 必须是非空字符串")

		local bounds = {}
		for _, territory in options.ListTerritories(defender) do
			if territory.ZoneId == regionId then
				table.insert(bounds, territory)
			end
		end
		if #bounds == 0 then
			return 0
		end

		local positions = {}
		for _, owner in options.GetPlayers() do
			if owner == defender then
				continue
			end
			for _, record in options.ListMonsters(owner) do
				local model = record.Model
				if not model or not model:IsDescendantOf(workspace) then
					continue
				end

				table.insert(positions, model:GetPivot().Position)
			end
		end
		return PlayerRegionMonsterOccupancyQuery.CountPositions(bounds, positions)
	end

	return table.freeze({
		Count = count,
		IsOccupied = function(defender: Player, regionId: string): boolean
			return count(defender, regionId) > 0
		end,
	})
end

return PlayerRegionMonsterOccupancyQuery
