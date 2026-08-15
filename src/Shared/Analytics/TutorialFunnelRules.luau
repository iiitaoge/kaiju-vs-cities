--[[
	职责：把当前新手引导 StepId 固定映射为分析漏斗阶段。
	输入：GetStep 接收 TutorialProgression 的 StepId。
	输出：稳定的阶段编号、StepId 和阶段名称。
	内部算法：按当前 TutorialProgression 的完整 11 步声明顺序建立只读索引。
	不负责：读取玩家状态、发送分析事件或推进引导。
]]

local TutorialProgression = require(script.Parent.Parent.Tutorial.TutorialProgression)

local TutorialFunnelRules = {}

export type Step = {
	Step: number,
	StepId: string,
	Name: string,
}

local STEP_IDS = table.freeze({
	"BuildR1",
	"CollectForR1Upgrade",
	"UpgradeR1",
	"CollectForMonsterBuild",
	"BuildMonster",
	"WaitForMonsterBuild",
	"StartAttack",
	"ChooseTarget",
	"CollectForDefenseMonsterBuild",
	"BuildDefenseMonster",
	"Complete",
})

local steps = {}
local stepsById = {}
for stepNumber, stepId in STEP_IDS do
	local definition = assert(
		TutorialProgression.GetDefinition(stepId),
		"新手引导漏斗缺少步骤定义：" .. stepId
	)
	local step: Step = table.freeze({
		Step = stepNumber,
		StepId = stepId,
		Name = definition.Title,
	})
	steps[stepNumber] = step
	stepsById[stepId] = step
end

local STEPS: { Step } = table.freeze(steps)
local STEPS_BY_ID: { [string]: Step } = table.freeze(stepsById)

function TutorialFunnelRules.GetSteps(): { Step }
	return STEPS
end

function TutorialFunnelRules.GetStep(stepId: string): Step?
	return STEPS_BY_ID[stepId]
end

return table.freeze(TutorialFunnelRules)
