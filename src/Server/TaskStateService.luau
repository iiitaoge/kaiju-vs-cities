--[[
	职责：保存玩家的任务运行时状态，并负责与任务存档片段互转。
	输入：player、任务存档片段或单个任务状态。
	输出：任务状态快照、Capture 可序列化表、Restore 恢复结果。
	内部算法：按当前 TaskConfigs 初始化缺失任务；恢复时用 TaskRules 重新规范化每个要求的进度。
	不负责：监听业务事件、判断任务完成、发放奖励或排队保存。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TaskConfigs = require(ReplicatedStorage.Shared.Task.TaskConfigs)
local TaskRules = require(ReplicatedStorage.Shared.Task.TaskRules)

local TaskStateService = {}

local statesByPlayer: { [Player]: { [string]: TaskRules.TaskState } } = setmetatable(
	{},
	{ __mode = "k" }
)

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function ensure(player: Player): { [string]: TaskRules.TaskState }
	local states = statesByPlayer[player]
	if states then
		return states
	end
	TaskStateService.Restore(player, nil)
	return assert(statesByPlayer[player])
end

function TaskStateService.Restore(player: Player, saved)
	assertPlayer(player)
	local source = if type(saved) == "table" then saved else {}
	local states = {}
	for taskId, definition in TaskConfigs.Tasks do
		states[taskId] = TaskRules.NormalizeState(definition, source[taskId])
	end
	statesByPlayer[player] = states
	return TaskStateService.GetAll(player)
end

function TaskStateService.Get(player: Player, taskId: string): TaskRules.TaskState?
	assertPlayer(player)
	local definition = TaskConfigs.Tasks[taskId]
	if not definition then
		return nil
	end
	local state = ensure(player)[taskId]
	return if state then TaskRules.CloneState(state) else nil
end

function TaskStateService.Set(player: Player, taskId: string, state: TaskRules.TaskState)
	assertPlayer(player)
	assert(TaskConfigs.Tasks[taskId] ~= nil, "未知任务：" .. tostring(taskId))
	local states = ensure(player)
	local cloned = TaskRules.CloneState(state)
	states[taskId] = cloned
	return TaskRules.CloneState(cloned)
end

function TaskStateService.GetAll(player: Player)
	assertPlayer(player)
	local states = ensure(player)
	local result = {}
	for taskId, state in states do
		result[taskId] = TaskRules.CloneState(state)
	end
	return result
end

function TaskStateService.Capture(player: Player)
	assertPlayer(player)
	return TaskStateService.GetAll(player)
end

return table.freeze(TaskStateService)
