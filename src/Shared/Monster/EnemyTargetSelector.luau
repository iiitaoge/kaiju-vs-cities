local EnemyTargetSelector = {}

local EPSILON = 1e-6

export type Candidate = {
	TargetId: string,
	OwnerUserId: number,
	Position: Vector3,
	Active: boolean,
}

export type SelectOptions = {
	TargetOwnerUserId: number,
	MaxDistance: number,
}

local function isFiniteNumber(value): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- 输入：搜索原点、候选目标和指定敌方玩家。
-- 输出：水平范围内最近的有效敌方目标；等距时按 TargetId 稳定选择。
-- 内部算法：只计算 X/Z 距离和身份过滤，不查询 Workspace 或玩家状态。
function EnemyTargetSelector.Select(
	origin: Vector3,
	candidates: { Candidate },
	options: SelectOptions
): Candidate?
	assert(typeof(origin) == "Vector3", "origin 必须是 Vector3")
	assert(type(candidates) == "table", "candidates 必须是 table")
	assert(type(options) == "table", "options 必须是 table")
	assert(isFiniteNumber(options.MaxDistance) and options.MaxDistance >= 0, "MaxDistance 无效")

	local best: Candidate? = nil
	local bestDistance = math.huge
	for _, candidate in candidates do
		if not candidate.Active or candidate.OwnerUserId ~= options.TargetOwnerUserId then
			continue
		end
		if type(candidate.TargetId) ~= "string" or candidate.TargetId == "" then
			continue
		end
		if typeof(candidate.Position) ~= "Vector3" then
			continue
		end

		local distance = (
			Vector2.new(candidate.Position.X, candidate.Position.Z)
			- Vector2.new(origin.X, origin.Z)
		).Magnitude
		if distance > options.MaxDistance + EPSILON then
			continue
		end
		if distance < bestDistance - EPSILON
			or (
				math.abs(distance - bestDistance) <= EPSILON
				and (not best or candidate.TargetId < best.TargetId)
			) then
			best = candidate
			bestDistance = distance
		end
	end

	return best
end

return EnemyTargetSelector
