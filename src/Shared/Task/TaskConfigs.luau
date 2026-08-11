--[[
	职责：提供任务内容配置入口。
	输入：无。
	输出：由任务 ID 索引的静态任务定义。
	内部算法：无；任务内容只在这里声明，运行时状态不进入本模块。
	不负责：玩家进度、事件上报、奖励发放或存档。

	首批任务：区域解锁。目标区域的前置区域和等级直接读取 Shared.World.ZoneCatalog，
	避免在任务配置中复制解锁条件。每个任务当前配置一个奖励项，奖励类型为钻石。
]]

local TaskProtocol = require(script.Parent.TaskProtocol)

local requirementKinds = TaskProtocol.RequirementKinds
local rewardKinds = TaskProtocol.RewardKinds

local function regionUnlockTask(
	taskId: string,
	order: number,
	zoneId: string,
	text: string,
	rewardAmount: number
)
	return {
		Id = taskId,
		Order = order,
		Text = text,
		Requirements = {
			{
				Id = "UnlockZone",
				Kind = requirementKinds.UnlockZone,
				Config = { ZoneId = zoneId },
			},
		},
		Reward = { Kind = rewardKinds.Diamond, Amount = rewardAmount },
	}
end

local tasks = {
	UnlockR3 = regionUnlockTask(
		"UnlockR3",
		1,
		"R3",
		"Upgrade Region 2 to Level 5, then unlock Region 3",
		100
	),
	UnlockR4 = regionUnlockTask(
		"UnlockR4",
		2,
		"R4",
		"Upgrade Region 3 to Level 5, then unlock Region 4",
		300
	),
	UnlockR5 = regionUnlockTask(
		"UnlockR5",
		3,
		"R5",
		"Upgrade Region 4 to Level 5, then unlock Region 5",
		800
	),
	UnlockR6 = regionUnlockTask(
		"UnlockR6",
		4,
		"R6",
		"Upgrade Region 5 to Level 5, then unlock Region 6",
		1_500
	),
}

for _, task in tasks do
	for _, requirement in task.Requirements do
		table.freeze(requirement.Config)
		table.freeze(requirement)
	end
	table.freeze(task.Reward)
	table.freeze(task.Requirements)
	table.freeze(task)
end

return table.freeze({
	Tasks = table.freeze(tasks),
})
