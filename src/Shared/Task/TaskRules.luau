--[[
	职责：提供与 Roblox Instance、玩家和存档无关的任务配置校验及进度规则。
	输入：任务定义、当前进度和服务器业务事实。
	输出：配置校验结果、初始/规范化状态，以及事件产生的新进度。
	内部算法：按 Requirement.Kind 分派小型规则；要求之间不互相读取，只由上层判断“全部完成”。
	不负责：监听事件、修改玩家状态、发放奖励或写入 DataStore。
]]

local ValueValidation = require(script.Parent.Parent.ValueValidation)
local TaskProtocol = require(script.Parent.TaskProtocol)
local ZoneCatalog = require(script.Parent.Parent.World.ZoneCatalog)

local TaskRules = {}

export type Requirement = {
	Id: string,
	Kind: string,
	Config: { [string]: any },
}

export type Reward = {
	Kind: string,
	Amount: number,
}

export type TaskDefinition = {
	Id: string,
	Order: number,
	Text: string,
	Requirements: { Requirement },
	Reward: Reward,
}

export type ProgressState = {
	Kind: string,
	Current: number,
	Completed: boolean,
}

export type TaskState = {
	Completed: boolean,
	Progress: { [string]: ProgressState },
}

local function isValidIdentifier(value): boolean
	return type(value) == "string"
		and value ~= ""
		and string.match(value, "^[A-Za-z0-9_.%-]+$") ~= nil
end

local function isPositiveNumber(value): boolean
	return ValueValidation.IsFiniteNumber(value) and value > 0
end

local function isPositiveInteger(value): boolean
	return isPositiveNumber(value) and value % 1 == 0
end

local function validateRequirement(requirement, taskId: string, index: number): (boolean, string?)
	if type(requirement) ~= "table" then
		return false, string.format("InvalidRequirement:%s:%d", taskId, index)
	end
	if not isValidIdentifier(requirement.Id) then
		return false, string.format("InvalidRequirementId:%s:%d", taskId, index)
	end
	if type(requirement.Kind) ~= "string" then
		return false, string.format("InvalidRequirementKind:%s:%s", taskId, requirement.Id)
	end
	if type(requirement.Config) ~= "table" then
		return false, string.format("InvalidRequirementConfig:%s:%s", taskId, requirement.Id)
	end

	local config = requirement.Config
	if requirement.Kind == TaskProtocol.RequirementKinds.UnlockZone then
		if not isValidIdentifier(config.ZoneId) then
			return false, "InvalidUnlockZoneId:" .. taskId .. ":" .. requirement.Id
		end
		if not ZoneCatalog.Get(config.ZoneId) then
			return false, "UnknownUnlockZoneId:" .. taskId .. ":" .. requirement.Id
		end
	elseif requirement.Kind == TaskProtocol.RequirementKinds.BuildHouse then
		if not isValidIdentifier(config.HouseId) then
			return false, "InvalidBuildHouseId:" .. taskId .. ":" .. requirement.Id
		end
	elseif requirement.Kind == TaskProtocol.RequirementKinds.UpgradeMonster then
		if config.SpawnPointId ~= nil and not isValidIdentifier(config.SpawnPointId) then
			return false, "InvalidUpgradeMonsterSpawnPoint:" .. taskId .. ":" .. requirement.Id
		end
		if not isPositiveInteger(config.TargetLevel) then
			return false, "InvalidUpgradeMonsterTargetLevel:" .. taskId .. ":" .. requirement.Id
		end
	elseif requirement.Kind == TaskProtocol.RequirementKinds.EarnMoney then
		if not isPositiveNumber(config.Amount) then
			return false, "InvalidEarnMoneyAmount:" .. taskId .. ":" .. requirement.Id
		end
	else
		return false, "UnsupportedRequirementKind:" .. tostring(requirement.Kind)
	end

	return true, nil
end

local function validateReward(reward, taskId: string, index: number): (boolean, string?)
	if type(reward) ~= "table" then
		return false, string.format("InvalidReward:%s:%d", taskId, index)
	end
	if reward.Kind ~= TaskProtocol.RewardKinds.Money
		and reward.Kind ~= TaskProtocol.RewardKinds.Diamond
	then
		return false, "UnsupportedRewardKind:" .. tostring(reward.Kind)
	end
	if not isPositiveNumber(reward.Amount) then
		return false, string.format("InvalidRewardAmount:%s:%d", taskId, index)
	end
	return true, nil
end

function TaskRules.ValidateConfig(config): (boolean, string?)
	if type(config) ~= "table" or type(config.Tasks) ~= "table" then
		return false, "InvalidTaskConfig"
	end

	local taskOrders = {}
	for taskId, task in config.Tasks do
		if not isValidIdentifier(taskId) or type(task) ~= "table" then
			return false, "InvalidTaskId"
		end
		if task.Id ~= taskId then
			return false, "TaskIdMismatch:" .. tostring(taskId)
		end
		if not isPositiveInteger(task.Order) then
			return false, "InvalidTaskOrder:" .. taskId
		end
		if type(task.Text) ~= "string" or task.Text == "" then
			return false, "InvalidTaskText:" .. taskId
		end
		if type(task.Requirements) ~= "table" or #task.Requirements == 0 then
			return false, "TaskRequirementsMissing:" .. taskId
		end
		if type(task.Reward) ~= "table" then
			return false, "TaskRewardMissing:" .. taskId
		end

		local requirementIds = {}
		if taskOrders[task.Order] then
			return false, "DuplicateTaskOrder:" .. tostring(task.Order)
		end
		taskOrders[task.Order] = true
		for index, requirement in task.Requirements do
			local valid, reason = validateRequirement(requirement, taskId, index)
			if not valid then
				return false, reason
			end
			if requirementIds[requirement.Id] then
				return false, "DuplicateRequirementId:" .. taskId .. ":" .. requirement.Id
			end
			requirementIds[requirement.Id] = true
		end
		local valid, reason = validateReward(task.Reward, taskId, 1)
		if not valid then
			return false, reason
		end
	end

	return true, nil
end

local function progressKindForRequirement(kind: string): string
	if kind == TaskProtocol.RequirementKinds.EarnMoney then
		return TaskProtocol.ProgressKinds.Counter
	elseif kind == TaskProtocol.RequirementKinds.UpgradeMonster then
		return TaskProtocol.ProgressKinds.Level
	end
	return TaskProtocol.ProgressKinds.Boolean
end

local function newProgress(requirement: Requirement): ProgressState
	return {
		Kind = progressKindForRequirement(requirement.Kind),
		Current = 0,
		Completed = false,
	}
end

function TaskRules.GetInitialState(task: TaskDefinition): TaskState
	local progress = {}
	for _, requirement in task.Requirements do
		progress[requirement.Id] = newProgress(requirement)
	end
	return {
		Completed = false,
		Progress = progress,
	}
end

function TaskRules.NormalizeState(task: TaskDefinition, saved): TaskState
	local state = TaskRules.GetInitialState(task)
	if type(saved) ~= "table" then
		return state
	end

	local savedProgress = if type(saved.Progress) == "table" then saved.Progress else {}
	for _, requirement in task.Requirements do
		local progress = state.Progress[requirement.Id]
		local rawProgress = savedProgress[requirement.Id]
		if type(rawProgress) ~= "table" then
			continue
		end

		local current = if ValueValidation.IsFiniteNumber(rawProgress.Current)
			then math.max(0, rawProgress.Current)
			else 0
		if requirement.Kind == TaskProtocol.RequirementKinds.UnlockZone
			or requirement.Kind == TaskProtocol.RequirementKinds.BuildHouse
		then
			current = if rawProgress.Completed == true then 1 else 0
		elseif requirement.Kind == TaskProtocol.RequirementKinds.UpgradeMonster then
			current = math.min(current, requirement.Config.TargetLevel)
		elseif requirement.Kind == TaskProtocol.RequirementKinds.EarnMoney then
			current = math.min(current, requirement.Config.Amount)
		end

		progress.Current = current
		progress.Completed = rawProgress.Completed == true
			or (requirement.Kind == TaskProtocol.RequirementKinds.UpgradeMonster
				and current >= requirement.Config.TargetLevel)
			or (requirement.Kind == TaskProtocol.RequirementKinds.EarnMoney
				and current >= requirement.Config.Amount)
	end
	state.Completed = saved.Completed == true
	return state
end

function TaskRules.CloneState(state: TaskState): TaskState
	local progress = {}
	for requirementId, value in state.Progress do
		progress[requirementId] = {
			Kind = value.Kind,
			Current = value.Current,
			Completed = value.Completed,
		}
	end
	return {
		Completed = state.Completed == true,
		Progress = progress,
	}
end

local function eventMatches(event, eventKind: string): boolean
	return type(event) == "table" and event.Kind == eventKind
end

function TaskRules.ApplyEvent(
	requirement: Requirement,
	progress: ProgressState,
	event
): ProgressState?
	if type(progress) ~= "table" or progress.Completed or type(event) ~= "table" then
		return nil
	end

	local config = requirement.Config
	if requirement.Kind == TaskProtocol.RequirementKinds.UnlockZone then
		if not eventMatches(event, TaskProtocol.EventKinds.ZoneUnlocked)
			or event.ZoneId ~= config.ZoneId
		then
			return nil
		end
		return {
			Kind = TaskProtocol.ProgressKinds.Boolean,
			Current = 1,
			Completed = true,
		}
	elseif requirement.Kind == TaskProtocol.RequirementKinds.BuildHouse then
		if not eventMatches(event, TaskProtocol.EventKinds.HouseBuilt)
			or event.HouseId ~= config.HouseId
		then
			return nil
		end
		return {
			Kind = TaskProtocol.ProgressKinds.Boolean,
			Current = 1,
			Completed = true,
		}
	elseif requirement.Kind == TaskProtocol.RequirementKinds.UpgradeMonster then
		if not eventMatches(event, TaskProtocol.EventKinds.MonsterUpgraded)
			or (config.SpawnPointId ~= nil and event.SpawnPointId ~= config.SpawnPointId)
			or not ValueValidation.IsFiniteNumber(event.TargetLevel)
			or event.TargetLevel < 1
		then
			return nil
		end
		local current = math.max(progress.Current, event.TargetLevel)
		current = math.min(current, config.TargetLevel)
		return {
			Kind = TaskProtocol.ProgressKinds.Level,
			Current = current,
			Completed = current >= config.TargetLevel,
		}
	elseif requirement.Kind == TaskProtocol.RequirementKinds.EarnMoney then
		if not eventMatches(event, TaskProtocol.EventKinds.MoneyEarned)
			or not ValueValidation.IsFiniteNumber(event.Amount)
			or event.Amount <= 0
		then
			return nil
		end
		local current = math.min(config.Amount, progress.Current + event.Amount)
		return {
			Kind = TaskProtocol.ProgressKinds.Counter,
			Current = current,
			Completed = current >= config.Amount,
		}
	end
	return nil
end

function TaskRules.AreAllRequirementsComplete(state: TaskState): boolean
	local hasRequirement = false
	for _, progress in state.Progress do
		hasRequirement = true
		if not progress.Completed then
			return false
		end
	end
	return hasRequirement
end

return table.freeze(TaskRules)
