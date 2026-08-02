local MonsterStateRules = {}

export type MonsterState =
	"IdleAtSpawn"
	| "MovingToTarget"
	| "AttackingStructure"
	| "Defending"
	| "FightingMonster"
	| "Returning"
	| "Defeated"
	| "Recovering"

export type PermissionResult = {
	Allowed: boolean,
	Reason: string?,
}

local transitions: { [string]: { [string]: boolean } } = {
	IdleAtSpawn = {
		MovingToTarget = true,
		Defending = true,
	},
	MovingToTarget = {
		AttackingStructure = true,
		FightingMonster = true,
		Returning = true,
		Defeated = true,
	},
	AttackingStructure = {
		MovingToTarget = true,
		FightingMonster = true,
		Returning = true,
		Defeated = true,
	},
	Defending = {
		FightingMonster = true,
		IdleAtSpawn = true,
		Returning = true,
		Defeated = true,
	},
	FightingMonster = {
		MovingToTarget = true,
		AttackingStructure = true,
		Defending = true,
		Returning = true,
		IdleAtSpawn = true,
		Defeated = true,
	},
	Returning = {
		IdleAtSpawn = true,
		Defeated = true,
	},
	Defeated = {
		Recovering = true,
	},
	Recovering = {
		IdleAtSpawn = true,
	},
}

local function result(allowed: boolean, reason: string?): PermissionResult
	return {
		Allowed = allowed,
		Reason = reason,
	}
end

function MonsterStateRules.IsKnown(state): boolean
	return type(state) == "string" and transitions[state] ~= nil
end

-- 输入：当前状态和目标状态。
-- 输出：是否允许状态转换。
-- 内部算法：查询固定状态转换表；相同状态是幂等成功。
function MonsterStateRules.CheckTransition(fromState, toState): PermissionResult
	if not MonsterStateRules.IsKnown(fromState) or not MonsterStateRules.IsKnown(toState) then
		return result(false, "UnknownState")
	end
	if fromState == toState then
		return result(true, nil)
	end
	if transitions[fromState][toState] then
		return result(true, nil)
	end
	return result(false, "InvalidStateTransition")
end

function MonsterStateRules.CheckAttack(state): PermissionResult
	if state == "IdleAtSpawn" then
		return result(true, nil)
	end
	return result(false, MonsterStateRules.IsKnown(state) and "MonsterBusy" or "UnknownState")
end

function MonsterStateRules.CheckUpgrade(state): PermissionResult
	if state == "IdleAtSpawn" then
		return result(true, nil)
	end
	return result(false, MonsterStateRules.IsKnown(state) and "MonsterBusy" or "UnknownState")
end

function MonsterStateRules.CheckDefend(state): PermissionResult
	if state == "IdleAtSpawn" then
		return result(true, nil)
	end
	return result(false, MonsterStateRules.IsKnown(state) and "MonsterBusy" or "UnknownState")
end

function MonsterStateRules.IsDamageable(state): boolean
	return MonsterStateRules.IsKnown(state)
		and state ~= "Defeated"
		and state ~= "Recovering"
end

return MonsterStateRules
