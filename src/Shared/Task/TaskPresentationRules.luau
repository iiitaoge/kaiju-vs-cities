--[[
	职责：把任务配置、任务状态和区域状态转换为单卡片 UI 快照。
	输入：任务配置、玩家任务状态、玩家 Zone 状态。
	输出：第一个未完成任务的文本、进度和奖励；没有任务时返回隐藏快照。
	内部算法：按 Order 选择第一个未完成任务；区域等级任务读取权威 Zone Level，
	区域解锁任务显示 0/1，多要求任务显示完成要求数。
	不负责：服务器状态写入、任务完成、发奖、Remote 或 UI Instance。
]]

local TaskProtocol = require(script.Parent.TaskProtocol)
local TaskPresentationProtocol = require(script.Parent.TaskPresentationProtocol)

local TaskPresentationRules = {}

type ZoneState = {
	Unlocked: boolean,
	Level: number,
}

local function orderedTasks(config): { any }
	local result = {}
	for _, task in config.Tasks do
		table.insert(result, task)
	end
	table.sort(result, function(left, right)
		if left.Order == right.Order then
			return left.Id < right.Id
		end
		return left.Order < right.Order
	end)
	return result
end

local function clampProgress(current: number, target: number): (number, number)
	local safeTarget = math.max(1, target)
	return math.clamp(math.max(0, current), 0, safeTarget), safeTarget
end

local function singleRequirementProgress(requirement, progress, zoneStates): (number, number)
	local kind = requirement.Kind
	local config = requirement.Config
	if kind == TaskProtocol.RequirementKinds.EarnMoney then
		return clampProgress(progress.Current, config.Amount)
	elseif kind == TaskProtocol.RequirementKinds.UpgradeMonster then
		return clampProgress(progress.Current, config.TargetLevel)
	elseif kind == TaskProtocol.RequirementKinds.ReachRegionLevel then
		local zoneState: ZoneState? = zoneStates[config.ZoneId]
		local currentLevel = if zoneState then zoneState.Level else progress.Current
		return clampProgress(currentLevel, config.TargetLevel)
	elseif kind == TaskProtocol.RequirementKinds.UnlockZone then
		return clampProgress(if progress.Completed then 1 else progress.Current, 1)
	end
	return clampProgress(if progress.Completed then 1 else progress.Current, 1)
end

local function taskProgress(task, state, zoneStates): (number, number)
	if #task.Requirements == 1 then
		local requirement = task.Requirements[1]
		local progress = state.Progress[requirement.Id]
		if progress then
			return singleRequirementProgress(requirement, progress, zoneStates)
		end
		return 0, 1
	end

	local completed = 0
	for _, requirement in task.Requirements do
		local progress = state.Progress[requirement.Id]
		if progress and progress.Completed then
			completed += 1
		end
	end
	return completed, #task.Requirements
end

function TaskPresentationRules.Build(
	config,
	states,
	zoneStates
): TaskPresentationProtocol.Snapshot
	for _, task in orderedTasks(config) do
		local state = states[task.Id]
		if state and not state.Completed then
			local reward = task.Reward
			local current, target = taskProgress(task, state, zoneStates)
			return {
				Visible = true,
				TaskId = task.Id,
				Text = task.Text,
				Current = current,
				Target = target,
				RewardKind = reward.Kind,
				RewardAmount = reward.Amount,
			}
		end
	end
	return { Visible = false }
end

return table.freeze(TaskPresentationRules)
