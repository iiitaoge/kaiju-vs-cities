--[[
	职责：提供任务内容配置入口。
	输入：无。
	输出：由任务 ID 索引的静态任务定义。
	内部算法：无；任务内容只在这里声明，运行时状态不进入本模块。
	不负责：玩家进度、事件上报、奖励发放或存档。

	区域成长任务把“前置区域升到目标等级”和“解锁下一区域”拆成两个任务。
	升级任务从 Shared.World.ZoneCatalog 读取目标区域的前置条件，避免复制等级门槛。
	拆分后的两项奖励之和保持原区域里程碑奖励不变。
]]

local TaskProtocol = require(script.Parent.TaskProtocol)
local ZoneCatalog = require(script.Parent.Parent.World.ZoneCatalog)

local requirementKinds = TaskProtocol.RequirementKinds
local rewardKinds = TaskProtocol.RewardKinds

local function regionLevelTask(
	taskId: string,
	order: number,
	nextZoneId: string,
	rewardAmount: number
)
	local nextZone = assert(ZoneCatalog.Get(nextZoneId), "未知目标区域：" .. nextZoneId)
	local zoneId = assert(
		nextZone.UnlockPrerequisiteZoneId,
		"目标区域没有升级前置：" .. nextZoneId
	)
	local targetLevel = assert(
		nextZone.UnlockPrerequisiteLevel,
		"目标区域没有升级等级：" .. nextZoneId
	)
	return {
		Id = taskId,
		Order = order,
		Text = string.format("Upgrade Region %s to Level %d", string.sub(zoneId, 2), targetLevel),
		Requirements = {
			{
				Id = "ReachRegionLevel",
				Kind = requirementKinds.ReachRegionLevel,
				Config = { ZoneId = zoneId, TargetLevel = targetLevel },
			},
		},
		Reward = { Kind = rewardKinds.Diamond, Amount = rewardAmount },
	}
end

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
	UpgradeR1To5 = regionLevelTask(
		"UpgradeR1To5",
		1,
		"R2",
		5
	),
	UnlockR2 = regionUnlockTask(
		"UnlockR2",
		2,
		"R2",
		"Unlock Region 2",
		5
	),
	UpgradeR2To5 = regionLevelTask(
		"UpgradeR2To5",
		3,
		"R3",
		10
	),
	UnlockR3 = regionUnlockTask(
		"UnlockR3",
		4,
		"R3",
		"Unlock Region 3",
		10
	),
	UpgradeR3To5 = regionLevelTask(
		"UpgradeR3To5",
		5,
		"R4",
		20
	),
	UnlockR4 = regionUnlockTask(
		"UnlockR4",
		6,
		"R4",
		"Unlock Region 4",
		20
	),
	UpgradeR4To5 = regionLevelTask(
		"UpgradeR4To5",
		7,
		"R5",
		40
	),
	UnlockR5 = regionUnlockTask(
		"UnlockR5",
		8,
		"R5",
		"Unlock Region 5",
		40
	),
	UpgradeR5To5 = regionLevelTask(
		"UpgradeR5To5",
		9,
		"R6",
		80
	),
	UnlockR6 = regionUnlockTask(
		"UnlockR6",
		10,
		"R6",
		"Unlock Region 6",
		80
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
