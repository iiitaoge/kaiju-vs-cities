local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HouseLifecycleRules = require(
	ReplicatedStorage.Shared.Building.HouseLifecycleRules
)

local HouseLifecycleRulesSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "HouseLifecycleRulesSpec: " .. message)
end

local function transition(currentState, eventKind, expectedState)
	local result = HouseLifecycleRules.Apply(currentState, eventKind)
	expect(result.Accepted, result.Reason or "状态转换被拒绝")
	expect(result.NewState == expectedState, "目标状态错误：" .. tostring(eventKind))
	return result.NewState
end

-- 输入：无。
-- 输出：正常生命周期、摧毁回滚、重建失败回退和非法转换全部符合合同时返回 true。
-- 内部算法：只驱动纯状态转换，不创建 Player、Instance 或定时任务。
function HouseLifecycleRulesSpec.Run(): boolean
	local state = transition("Unbuilt", "Build", "Alive")
	state = transition(state, "Destroy", "Destroyed")
	state = transition(state, "BeginRebuild", "Rebuilding")
	state = transition(state, "CompleteRebuild", "Alive")
	expect(state == "Alive", "完整生命周期没有恢复 Alive")

	local rollback = transition("Destroyed", "RollbackDestroy", "Alive")
	expect(rollback == "Alive", "摧毁事务回滚错误")
	local aborted = transition("Rebuilding", "AbortRebuild", "Destroyed")
	expect(aborted == "Destroyed", "重建失败没有回到 Destroyed")

	local invalid = HouseLifecycleRules.Apply("Alive", "CompleteRebuild")
	expect(not invalid.Accepted and invalid.Reason == "InvalidTransition", "非法转换未被拒绝")
	expect(invalid.NewState == "Alive", "非法转换不应改变状态")
	return true
end

return HouseLifecycleRulesSpec
