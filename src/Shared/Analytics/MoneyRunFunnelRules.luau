--[[
	职责：定义“单次重生本轮收入”漏斗的固定门槛和逐级补齐规则。
	输入：当前本轮累计收入、调用方已经成功上报的最后步骤。
	输出：按收入从低到高返回本次应该上报的门槛步骤。
	内部算法：门槛表严格递增；单次收入跨过多个门槛时返回所有中间步骤，避免漏掉阶段。
	不负责：读取玩家状态、发送分析事件或改变金币。
]]

local MoneyRunFunnelRules = {}

export type Step = {
	Step: number,
	Threshold: number,
	Name: string,
}

local function makeStep(step: number, threshold: number, name: string): Step
	return table.freeze({
		Step = step,
		Threshold = threshold,
		Name = name,
	})
end

local STEPS: { Step } = table.freeze({
	makeStep(1, 10, "10 Gold"),
	makeStep(2, 50, "50 Gold"),
	makeStep(3, 100, "100 Gold"),
	makeStep(4, 250, "250 Gold"),
	makeStep(5, 500, "500 Gold"),
	makeStep(6, 1_000, "1K Gold"),
	makeStep(7, 2_500, "2.5K Gold"),
	makeStep(8, 5_000, "5K Gold"),
	makeStep(9, 10_000, "10K Gold"),
	makeStep(10, 25_000, "25K Gold"),
	makeStep(11, 50_000, "50K Gold"),
	makeStep(12, 100_000, "100K Gold"),
	makeStep(13, 250_000, "250K Gold"),
	makeStep(14, 500_000, "500K Gold"),
	makeStep(15, 1_000_000, "1M Gold"),
})

local function assertFiniteNonNegative(value: number, name: string)
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value >= 0,
		name .. " 必须是有限非负数"
	)
end

function MoneyRunFunnelRules.GetSteps(): { Step }
	return STEPS
end

function MoneyRunFunnelRules.GetCrossedSteps(
	runEarnings: number,
	lastCompletedStep: number
): { Step }
	assertFiniteNonNegative(runEarnings, "runEarnings")
	assertFiniteNonNegative(lastCompletedStep, "lastCompletedStep")
	assert(lastCompletedStep % 1 == 0, "lastCompletedStep 必须是整数")

	local crossed: { Step } = {}
	for stepNumber = lastCompletedStep + 1, #STEPS do
		local step = STEPS[stepNumber]
		if not step or runEarnings < step.Threshold then
			break
		end
		table.insert(crossed, step)
	end
	return crossed
end

return table.freeze(MoneyRunFunnelRules)
