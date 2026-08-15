--[[
	职责：定义新手引导的英文文案、目标类型，并由权威进度快照解析当前步骤。
	输入：Resolve 接收完成版本、首次攻击完成状态、R1 等级、余额、三项权威费用、M1-S1/DM-R1 建造状态和事务状态。
	输出：稳定 StepId；GetDefinition 返回该步骤的纯表现配置。
	内部算法：按建造 R1 → 升级 R1 → 建造进攻怪兽 → 发起攻击 → 建造防守怪兽顺序判断。
	不负责：读取玩家状态、查找场景实例、显示 UI、绘制 Beam 或写入存档。
]]

local TutorialProgression = {}

export type StepId =
	"BuildR1"
	| "CollectForR1Upgrade"
	| "UpgradeR1"
	| "CollectForMonsterBuild"
	| "BuildMonster"
	| "WaitForMonsterBuild"
	| "CollectForDefenseMonsterBuild"
	| "BuildDefenseMonster"
	| "StartAttack"
	| "ChooseTarget"
	| "Complete"

export type Input = {
	CompletedVersion: number,
	AttackCompleted: boolean,
	R1Level: number,
	Money: number,
	R1UpgradeCost: number,
	FirstMonsterBuildCost: number,
	FirstMonsterBuilt: boolean,
	FirstMonsterBuildInProgress: boolean,
	FirstDefenseMonsterBuildCost: number,
	FirstDefenseMonsterBuilt: boolean,
}

export type Definition = {
	Title: string,
	Info: string,
	TargetKind: string?,
	AmountKey: string?,
}

TutorialProgression.CurrentVersion = 2
-- 旧版 Version=1 表示旧教程已完成，其中已经包含首次攻击；兼容旧存档时视为攻击完成。
TutorialProgression.AttackCompletedVersion = 1

local DEFINITIONS: { [StepId]: Definition } = {
	BuildR1 = table.freeze({
		Title = "BUILD YOUR CITY",
		Info = "Step on the green button to build your first city.",
		TargetKind = "R1ConstructionButton",
	}),
	CollectForR1Upgrade = table.freeze({
		Title = "COLLECT CASH",
		Info = "Walk into a glowing building and collect %s.",
		TargetKind = "R1Building",
		AmountKey = "R1UpgradeCost",
	}),
	UpgradeR1 = table.freeze({
		Title = "UPGRADE YOUR CITY",
		Info = "Step on the upgrade button to reach City Lv.2.",
		TargetKind = "R1ConstructionButton",
	}),
	CollectForMonsterBuild = table.freeze({
		Title = "PREPARE YOUR MONSTER",
		Info = "Keep collecting cash until you have %s.",
		TargetKind = "R1MonsterBuildBuilding",
		AmountKey = "FirstMonsterBuildCost",
	}),
	BuildMonster = table.freeze({
		Title = "BUILD GODZILLA",
		Info = "Step on the button to build your first Godzilla.",
		TargetKind = "FirstMonsterButton",
	}),
	WaitForMonsterBuild = table.freeze({
		Title = "BUILDING GODZILLA",
		Info = "Wait for the incubator to finish building.",
		TargetKind = nil,
	}),
	CollectForDefenseMonsterBuild = table.freeze({
		Title = "PREPARE YOUR DEFENSE",
		Info = "Keep collecting cash until you have %s.",
		TargetKind = "R1DefenseMonsterBuildBuilding",
		AmountKey = "FirstDefenseMonsterBuildCost",
	}),
	BuildDefenseMonster = table.freeze({
		Title = "BUILD DEFENSE KAIJU",
		Info = "Step on the button to build your defense kaiju.",
		TargetKind = "FirstDefenseMonsterButton",
	}),
	StartAttack = table.freeze({
		Title = "START AN ATTACK",
		Info = "Approach the incubator and press Start.",
		TargetKind = "FirstMonsterIncubator",
	}),
	ChooseTarget = table.freeze({
		Title = "CHOOSE A TARGET",
		Info = "Choose another city and confirm where to attack.",
		TargetKind = nil,
	}),
	Complete = table.freeze({
		Title = "TUTORIAL COMPLETE",
		Info = "Godzilla is on the way! Destroy buildings to earn rewards.",
		TargetKind = nil,
	}),
}
table.freeze(DEFINITIONS)

local function assertNonNegativeInteger(value: number, name: string)
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value >= 0
			and value % 1 == 0,
		name .. " must be a finite non-negative integer"
	)
end

local function assertNonNegativeNumber(value: number, name: string)
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value >= 0,
		name .. " must be a finite non-negative number"
	)
end

function TutorialProgression.Resolve(input: Input): StepId
	assert(type(input) == "table", "input must be a table")
	assertNonNegativeInteger(input.CompletedVersion, "CompletedVersion")
	assertNonNegativeInteger(input.R1Level, "R1Level")
	assertNonNegativeNumber(input.Money, "Money")
	assertNonNegativeNumber(input.R1UpgradeCost, "R1UpgradeCost")
	assertNonNegativeNumber(input.FirstMonsterBuildCost, "FirstMonsterBuildCost")
	assert(type(input.FirstMonsterBuilt) == "boolean", "FirstMonsterBuilt must be boolean")
	assert(type(input.AttackCompleted) == "boolean", "AttackCompleted must be boolean")
	assert(
		type(input.FirstMonsterBuildInProgress) == "boolean",
		"FirstMonsterBuildInProgress must be boolean"
	)
	assertNonNegativeNumber(
		input.FirstDefenseMonsterBuildCost,
		"FirstDefenseMonsterBuildCost"
	)
	assert(
		type(input.FirstDefenseMonsterBuilt) == "boolean",
		"FirstDefenseMonsterBuilt must be boolean"
	)

	if input.CompletedVersion >= TutorialProgression.CurrentVersion then
		return "Complete"
	end
	if input.R1Level < 1 then
		return "BuildR1"
	end
	if input.R1Level < 2 then
		return if input.Money < input.R1UpgradeCost
			then "CollectForR1Upgrade"
			else "UpgradeR1"
	end
	if not input.FirstMonsterBuilt then
		if input.FirstMonsterBuildInProgress then
			return "WaitForMonsterBuild"
		end
		return if input.Money < input.FirstMonsterBuildCost
			then "CollectForMonsterBuild"
			else "BuildMonster"
	end
	local attackCompleted = input.AttackCompleted
		or input.CompletedVersion >= TutorialProgression.AttackCompletedVersion
	if not attackCompleted then
		return "StartAttack"
	end
	if not input.FirstDefenseMonsterBuilt then
		return if input.Money < input.FirstDefenseMonsterBuildCost
			then "CollectForDefenseMonsterBuild"
			else "BuildDefenseMonster"
	end
	return "Complete"
end

function TutorialProgression.GetDefinition(stepId: StepId): Definition?
	return DEFINITIONS[stepId]
end

return table.freeze(TutorialProgression)
