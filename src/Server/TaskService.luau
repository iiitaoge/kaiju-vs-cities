--[[
	职责：组装任务配置、进度规则、服务器事实和自动奖励。
	输入：Start 无参数；Report 接收 player、已经成功的服务器事实；GetState 接收 player。
	输出：Report 返回进度是否变化、完成任务和已发放奖励；GetState 返回任务状态快照。
	内部算法：事实匹配每个未完成要求 → 写入该要求进度 → 所有要求完成后发放全部奖励 → 标记任务完成
	→ 将最新玩家状态排入现有持久化队列。
	不负责：产生业务事实、客户端请求校验、任务 UI、重复任务周期或倒计时。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataReadyService = require(script.Parent.PlayerDataReadyService)
local PlayerPersistenceCoordinator = require(script.Parent.PlayerPersistenceCoordinator)
local TaskEventBus = require(script.Parent.TaskEventBus)
local TaskRewardService = require(script.Parent.TaskRewardService)
local TaskStateService = require(script.Parent.TaskStateService)
local RegionStateService = require(script.Parent.RegionStateService)
local TaskConfigs = require(ReplicatedStorage.Shared.Task.TaskConfigs)
local TaskProtocol = require(ReplicatedStorage.Shared.Task.TaskProtocol)
local TaskRules = require(ReplicatedStorage.Shared.Task.TaskRules)

local TaskService = {}

export type ReportResult = {
	Changed: boolean,
	Reason: string?,
	CompletedTaskIds: { string },
	GrantedRewards: { [number]: any },
}

local started = false
local reporting: { [Player]: boolean } = setmetatable({}, { __mode = "k" })

local function emptyResult(reason: string?): ReportResult
	return {
		Changed = false,
		Reason = reason,
		CompletedTaskIds = {},
		GrantedRewards = {},
	}
end

local function canProcess(player: Player): (boolean, string?)
	local readiness = PlayerDataReadyService.Get(player)
	if readiness.Status == "Unmanaged" then
		return true, nil
	end
	if readiness.Status ~= "Ready" or not readiness.CanSave then
		return false, "PlayerDataNotReady"
	end
	return true, nil
end

local function queueSave(player: Player)
	local queued, reason = PlayerPersistenceCoordinator.SavePlayer(player)
	if not queued then
		warn(string.format(
			"任务进度已更新但立即存档未入队：%s (%s)",
			player.Name,
			tostring(reason)
		))
	end
end

local function appendGrantResult(
	result: ReportResult,
	taskId: string,
	grant
)
	for _, reward in grant.Rewards or {} do
		table.insert(result.GrantedRewards, {
			TaskId = taskId,
			Reward = reward,
		})
	end
end

local function tryCompleteTask(
	player: Player,
	taskId: string,
	definition,
	state,
	result: ReportResult
): boolean
	if state.Completed or not TaskRules.AreAllRequirementsComplete(state) then
		return false
	end

	local grant = TaskRewardService.Grant(player, { definition.Reward })
	if not grant.Succeeded then
		warn(string.format(
			"任务完成但奖励未发放：%s/%s (%s)",
			player.Name,
			taskId,
			tostring(grant.Reason)
		))
		return false
	end

	state.Completed = true
	TaskStateService.Set(player, taskId, state)
	result.Changed = true
	table.insert(result.CompletedTaskIds, taskId)
	appendGrantResult(result, taskId, grant)
	return true
end

local function reconcileAuthoritativeRequirements(player: Player, definition, state): boolean
	local stateChanged = false
	for _, requirement in definition.Requirements do
		local progress = state.Progress[requirement.Id]
		if not progress or progress.Completed then
			continue
		end

		local event = nil
		if requirement.Kind == TaskProtocol.RequirementKinds.UnlockZone then
			if RegionStateService.GetUnlocked(player, requirement.Config.ZoneId) then
				event = {
					Kind = TaskProtocol.EventKinds.ZoneUnlocked,
					ZoneId = requirement.Config.ZoneId,
				}
			end
		elseif requirement.Kind == TaskProtocol.RequirementKinds.ReachRegionLevel then
			event = {
				Kind = TaskProtocol.EventKinds.RegionLevelChanged,
				ZoneId = requirement.Config.ZoneId,
				Level = RegionStateService.GetLevel(player, requirement.Config.ZoneId),
			}
		end
		if not event then
			continue
		end

		local nextProgress = TaskRules.ApplyEvent(
			requirement,
			progress,
			event
		)
		if nextProgress
			and (nextProgress.Kind ~= progress.Kind
				or nextProgress.Current ~= progress.Current
				or nextProgress.Completed ~= progress.Completed)
		then
			state.Progress[requirement.Id] = nextProgress
			stateChanged = true
		end
	end
	return stateChanged
end

local function reconcileInternal(player: Player): ReportResult
	local result = emptyResult(nil)
	for taskId, definition in TaskConfigs.Tasks do
		local state = TaskStateService.Get(player, taskId)
		if not state or state.Completed then
			continue
		end

		if reconcileAuthoritativeRequirements(player, definition, state) then
			TaskStateService.Set(player, taskId, state)
			result.Changed = true
		end
		tryCompleteTask(player, taskId, definition, state, result)
	end
	return result
end

function TaskService.Report(player: Player, event): ReportResult
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	assert(type(event) == "table", "event 必须是 table")

	local ready, readyReason = canProcess(player)
	if not ready then
		return emptyResult(readyReason)
	end
	if reporting[player] then
		return emptyResult("TaskReportBusy")
	end
	reporting[player] = true

	local succeeded, resultOrError = xpcall(function()
		local result = emptyResult(nil)
		for taskId, definition in TaskConfigs.Tasks do
			local state = TaskStateService.Get(player, taskId)
			if not state or state.Completed then
				continue
			end

			local stateChanged = false
			for _, requirement in definition.Requirements do
				local progress = state.Progress[requirement.Id]
				if progress and not progress.Completed then
					local nextProgress = TaskRules.ApplyEvent(requirement, progress, event)
					if nextProgress then
						state.Progress[requirement.Id] = nextProgress
						stateChanged = true
					end
				end
			end

			if stateChanged then
				TaskStateService.Set(player, taskId, state)
				result.Changed = true
			end

			tryCompleteTask(player, taskId, definition, state, result)
		end

		if result.Changed then
			queueSave(player)
		end
		return result
	end, debug.traceback)

	reporting[player] = nil
	if not succeeded then
		warn(string.format("任务进度处理异常：%s (%s)", player.Name, tostring(resultOrError)))
		return emptyResult("TaskReportFailed")
	end
	return resultOrError
end

function TaskService.Reconcile(player: Player): ReportResult
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")

	local ready, readyReason = canProcess(player)
	if not ready then
		return emptyResult(readyReason)
	end
	if reporting[player] then
		return emptyResult("TaskReportBusy")
	end
	reporting[player] = true

	local succeeded, resultOrError = xpcall(function()
		local result = reconcileInternal(player)
		if result.Changed then
			queueSave(player)
		end
		return result
	end, debug.traceback)

	reporting[player] = nil
	if not succeeded then
		warn(string.format("任务状态同步异常：%s (%s)", player.Name, tostring(resultOrError)))
		return emptyResult("TaskReconcileFailed")
	end
	return resultOrError
end

function TaskService.GetState(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	return TaskStateService.GetAll(player)
end

function TaskService.GetTaskState(player: Player, taskId: string)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	return TaskStateService.Get(player, taskId)
end

function TaskService.Start()
	if started then
		return
	end
	local valid, reason = TaskRules.ValidateConfig(TaskConfigs)
	assert(valid, reason or "InvalidTaskConfig")
	started = true
	TaskEventBus.Connect(function(player: Player, event)
		TaskService.Report(player, event)
	end)
end

return table.freeze(TaskService)
