--[[
	职责：验证区域敌方怪兽占用查询的 Bounds 判定、重叠去重和多怪兽计数。
	输入：无。
	输出：全部约束通过时返回 true。
	内部算法：用纯 Bounds 和 Pivot 位置快照驱动查询，不依赖正式玩家或 Workspace 状态。
]]

local PlayerRegionMonsterOccupancyQuery = require(
	script.Parent.Parent.PlayerRegionMonsterOccupancyQuery
)

local PlayerRegionMonsterOccupancyQuerySpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "PlayerRegionMonsterOccupancyQuerySpec: " .. message)
end

function PlayerRegionMonsterOccupancyQuerySpec.Run(): boolean
	local bounds = {
		{ CFrame = CFrame.identity, Size = Vector3.new(10, 1, 10) },
		{ CFrame = CFrame.new(8, 0, 0), Size = Vector3.new(10, 1, 10) },
	}

	expect(
		PlayerRegionMonsterOccupancyQuery.CountPositions(bounds, {
			Vector3.new(4, 0, 0),
			Vector3.new(-4, 0, 0),
			Vector3.new(20, 0, 0),
		}) == 2,
		"两只区域内怪兽没有各计数一次"
	)
	expect(
		PlayerRegionMonsterOccupancyQuery.CountPositions(bounds, {
			Vector3.new(4, 0, 0),
		}) == 1,
		"同一只怪兽命中重叠 Bounds 时被重复计数"
	)
	expect(
		PlayerRegionMonsterOccupancyQuery.CountPositions(bounds, {
			Vector3.new(-20, 0, 0),
			Vector3.new(20, 0, 0),
		}) == 0,
		"区域外怪兽不应计入占用"
	)
	return true
end

return PlayerRegionMonsterOccupancyQuerySpec
