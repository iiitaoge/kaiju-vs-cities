local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterExpeditionReportBuilder = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionReportBuilder
)

local MonsterExpeditionReportBuilderSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "MonsterExpeditionReportBuilderSpec: " .. message)
end

function MonsterExpeditionReportBuilderSpec.Run(): boolean
	local context = {
		CommandId = 8,
		AttackerUserId = 1,
		DefenderUserId = 2,
		AttackerSpawnPointId = "M1-S1",
		MonsterKey = "Godzilla-L001",
		EntryPoint = Vector3.new(10, 0, 20),
		StartedAt = 100,
	}
	local completed = MonsterExpeditionReportBuilder.Build(context, true, {
		Succeeded = true,
		EndReason = "Completed",
		Reason = nil,
		DestroyedHouseIds = { "R1-H1", "R1-H1", "R1-H2" },
		RewardGranted = 20,
		DefeatedDefenderMonsterIds = { "M1-S2", "M1-S2" },
		AttackerDefeated = false,
		TowerHitCount = 3,
		TowerDamageTaken = 15,
	}, 112)
	expect(completed.Duration == 12 and completed.Succeeded, "完成报告基本字段错误")
	expect(#completed.DestroyedHouseIds == 2, "房屋 ID 必须稳定去重")
	expect(#completed.DefeatedDefenderMonsterIds == 1, "防守怪兽 ID 必须稳定去重")
	expect(completed.RewardGranted == 20, "奖励汇总错误")
	expect(completed.TowerHitCount == 3 and completed.TowerDamageTaken == 15, "塔伤统计错误")

	local failed = MonsterExpeditionReportBuilder.Build(context, false, "trace", 101)
	expect(
		not failed.Succeeded and failed.EndReason == "Failed" and failed.Reason == "ExecutionError",
		"执行异常必须转换为稳定失败报告"
	)
	expect(failed.RewardGranted == 0 and #failed.DestroyedHouseIds == 0, "失败报告不得伪造战果")
	return true
end

return MonsterExpeditionReportBuilderSpec
