--[[
	职责：读取目标 Plot 某个收入区域的三处怪兽接敌定位点。
	输入：目标 Plot、RegionId。
	输出：进攻出生点、防守出生点和相遇中心，或稳定失败原因。
	不负责：玩家权限、区域解锁、怪兽移动、状态切换或战斗。
]]

local UniqueNamedChildAccess = require(script.Parent.UniqueNamedChildAccess)
local WorkspaceDefenseMonsterSlotAccess = require(
	script.Parent.WorkspaceDefenseMonsterSlotAccess
)

local WorkspaceMonsterEncounterAccess = {}

local ATTACK_SPAWN_NAME = "AttackMonsterSpawnPoint"
local ENCOUNTER_POINT_NAME = "EncounterPoint"

export type Points = {
	AttackMonsterSpawnPoint: BasePart,
	DefenseMonsterSpawnPoint: BasePart,
	EncounterPoint: BasePart,
}

local function resolvePart(zone: Instance, name: string, missingReason: string): (BasePart?, string?)
	local instance, duplicated = UniqueNamedChildAccess.Find(zone, name)
	if duplicated then
		return nil, "Duplicate" .. name
	end
	if not instance then
		return nil, missingReason
	end
	if not instance:IsA("BasePart") then
		return nil, name .. "MustBeBasePart"
	end
	return instance, nil
end

function WorkspaceMonsterEncounterAccess.Resolve(
	plot: Model,
	regionId: string
): (Points?, string?)
	if typeof(plot) ~= "Instance" or not plot:IsA("Model") then
		return nil, "InvalidPlot"
	end
	if type(regionId) ~= "string" or regionId == "" then
		return nil, "InvalidRegionId"
	end

	local zones = plot:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(regionId)
	if not zone or not (zone:IsA("Folder") or zone:IsA("Model")) then
		return nil, "MissingMonsterEncounterRegion"
	end

	local defenseSpawnPoint, defenseReason = WorkspaceDefenseMonsterSlotAccess.Resolve(
		plot,
		regionId
	)
	if not defenseSpawnPoint then
		return nil, defenseReason or "MissingDefenseMonsterSpawnPoint"
	end

	local attackSpawnPoint, attackReason = resolvePart(
		zone,
		ATTACK_SPAWN_NAME,
		"MissingAttackMonsterSpawnPoint"
	)
	if not attackSpawnPoint then
		return nil, attackReason
	end

	local encounterPoint, encounterReason = resolvePart(
		zone,
		ENCOUNTER_POINT_NAME,
		"MissingEncounterPoint"
	)
	if not encounterPoint then
		return nil, encounterReason
	end

	return {
		AttackMonsterSpawnPoint = attackSpawnPoint,
		DefenseMonsterSpawnPoint = defenseSpawnPoint,
		EncounterPoint = encounterPoint,
	}, nil
end

return WorkspaceMonsterEncounterAccess
