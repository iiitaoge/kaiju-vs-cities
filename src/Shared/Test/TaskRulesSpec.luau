local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TaskProtocol = require(ReplicatedStorage.Shared.Task.TaskProtocol)
local TaskRules = require(ReplicatedStorage.Shared.Task.TaskRules)

local TaskRulesSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "TaskRulesSpec: " .. message)
end

function TaskRulesSpec.Run(): boolean
	local task = {
		Id = "TaskA",
		Order = 1,
		Text = "测试任务",
		Requirements = {
			{
				Id = "Zone",
				Kind = TaskProtocol.RequirementKinds.UnlockZone,
				Config = { ZoneId = "R2" },
			},
			{
				Id = "House",
				Kind = TaskProtocol.RequirementKinds.BuildHouse,
				Config = { HouseId = "R2-H1" },
			},
			{
				Id = "Monster",
				Kind = TaskProtocol.RequirementKinds.UpgradeMonster,
				Config = { SpawnPointId = "M1-S1", TargetLevel = 2 },
			},
			{
				Id = "Money",
				Kind = TaskProtocol.RequirementKinds.EarnMoney,
				Config = { Amount = 100 },
			},
		},
		Reward = { Kind = TaskProtocol.RewardKinds.Diamond, Amount = 2 },
	}
	local valid, reason = TaskRules.ValidateConfig({ Tasks = { TaskA = task } })
	expect(valid and reason == nil, "多要求任务配置必须有效")

	local state = TaskRules.GetInitialState(task)
	local zoneProgress = TaskRules.ApplyEvent(
		task.Requirements[1],
		state.Progress.Zone,
		{ Kind = TaskProtocol.EventKinds.ZoneUnlocked, ZoneId = "R2" }
	)
	expect(zoneProgress ~= nil and zoneProgress.Completed, "区域解锁要求完成错误")
	state.Progress.Zone = zoneProgress

	local houseProgress = TaskRules.ApplyEvent(
		task.Requirements[2],
		state.Progress.House,
		{ Kind = TaskProtocol.EventKinds.HouseBuilt, HouseId = "R2-H1" }
	)
	expect(houseProgress ~= nil and houseProgress.Completed, "房屋建造要求完成错误")
	state.Progress.House = houseProgress

	local wrongMonster = TaskRules.ApplyEvent(
		task.Requirements[3],
		state.Progress.Monster,
		{ Kind = TaskProtocol.EventKinds.MonsterUpgraded, SpawnPointId = "M1-S2", TargetLevel = 2 }
	)
	expect(wrongMonster == nil, "不匹配的怪兽不得推进任务")
	local monsterProgress = TaskRules.ApplyEvent(
		task.Requirements[3],
		state.Progress.Monster,
		{ Kind = TaskProtocol.EventKinds.MonsterUpgraded, SpawnPointId = "M1-S1", TargetLevel = 2 }
	)
	expect(monsterProgress ~= nil and monsterProgress.Completed, "怪兽升级要求完成错误")
	state.Progress.Monster = monsterProgress

	local firstMoneyProgress = TaskRules.ApplyEvent(
		task.Requirements[4],
		state.Progress.Money,
		{ Kind = TaskProtocol.EventKinds.MoneyEarned, Amount = 40 }
	)
	expect(firstMoneyProgress ~= nil and firstMoneyProgress.Current == 40, "金币进度累计错误")
	local secondMoneyProgress = TaskRules.ApplyEvent(
		task.Requirements[4],
		firstMoneyProgress,
		{ Kind = TaskProtocol.EventKinds.MoneyEarned, Amount = 70 }
	)
	expect(
		secondMoneyProgress ~= nil
			and secondMoneyProgress.Current == 100
			and secondMoneyProgress.Completed,
		"金币进度完成和上限错误"
	)
	state.Progress.Money = secondMoneyProgress
	expect(TaskRules.AreAllRequirementsComplete(state), "全部要求完成判断错误")

	local normalized = TaskRules.NormalizeState(task, {
		Completed = true,
		Progress = {
			Money = { Kind = "Counter", Current = 999, Completed = true },
		},
	})
	expect(normalized.Completed and normalized.Progress.Money.Current == 100, "任务状态规范化错误")
	return true
end

return TaskRulesSpec
