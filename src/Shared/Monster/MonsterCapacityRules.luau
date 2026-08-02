local MonsterCapacityRules = {}

export type RuleResult = {
	Allowed: boolean,
	Reason: string?,
	Count: number,
	Capacity: number,
}

local function isNonNegativeInteger(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value >= 0
		and value % 1 == 0
end

-- 输入：当前怪兽数量和当前容量。
-- 输出：是否允许新增一只怪兽，以及稳定失败原因。
-- 内部算法：只比较数量和容量，不读取玩家、建筑或升级状态。
function MonsterCapacityRules.CheckAdd(currentCount: number, capacity: number): RuleResult
	if not isNonNegativeInteger(currentCount) then
		return {
			Allowed = false,
			Reason = "InvalidCount",
			Count = 0,
			Capacity = capacity,
		}
	end
	if not isNonNegativeInteger(capacity) then
		return {
			Allowed = false,
			Reason = "InvalidCapacity",
			Count = currentCount,
			Capacity = 0,
		}
	end
	if currentCount >= capacity then
		return {
			Allowed = false,
			Reason = "CapacityReached",
			Count = currentCount,
			Capacity = capacity,
		}
	end

	return {
		Allowed = true,
		Reason = nil,
		Count = currentCount,
		Capacity = capacity,
	}
end

-- 输入：当前怪兽数量和准备写入的新容量。
-- 输出：容量值是否合法。容量可以暂时低于已有数量，但不会删除怪兽。
-- 内部算法：只验证有限非负整数，不推断容量增长来源。
function MonsterCapacityRules.CheckSet(currentCount: number, newCapacity: number): RuleResult
	if not isNonNegativeInteger(currentCount) then
		return {
			Allowed = false,
			Reason = "InvalidCount",
			Count = 0,
			Capacity = newCapacity,
		}
	end
	if not isNonNegativeInteger(newCapacity) then
		return {
			Allowed = false,
			Reason = "InvalidCapacity",
			Count = currentCount,
			Capacity = 0,
		}
	end

	return {
		Allowed = true,
		Reason = nil,
		Count = currentCount,
		Capacity = newCapacity,
	}
end

return MonsterCapacityRules
