local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterStateRules = require(ReplicatedStorage.Shared.Monster.MonsterStateRules)

local MonsterUpgradeCoordinator = {}

-- 输入：升级逻辑已确定的新怪兽身份、Home CFrame、Start 模板、绝对 Scale、最大生命和模板是否变化。
-- 输出：是否完成升级，以及升级后的记录。
-- 内部算法：同形态保留原 Model、缩放并满血更新身份；换形态才预隐藏替换 Model。
-- 不负责：价格、建筑等级、升级条件和配置映射。
function MonsterUpgradeCoordinator.Execute(
	player: Player,
	spawnPointId: string,
	newMonsterKey: string,
	template: Model,
	modelScale: number,
	spawnPoint: BasePart,
	homeCFrame: CFrame,
	maxHealth: number,
	templateChanged: boolean
)
	assert(type(templateChanged) == "boolean", "templateChanged 必须是 boolean")
	local current = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not current then
		return {
			Succeeded = false,
			Reason = "UnknownSpawnPoint",
			Record = nil,
		}
	end
	local permission = MonsterStateRules.CheckUpgrade(current.State)
	if not permission.Allowed then
		return {
			Succeeded = false,
			Reason = permission.Reason,
			Record = current,
		}
	end

	if not templateChanged then
		return MonsterRosterCoordinator.UpgradeInPlace(
			player,
			spawnPointId,
			newMonsterKey,
			modelScale,
			spawnPoint,
			homeCFrame,
			maxHealth
		)
	end

	return MonsterRosterCoordinator.ReplaceForSpawnPoint(
		player,
		spawnPointId,
		newMonsterKey,
		template,
		modelScale,
		spawnPoint,
		homeCFrame,
		maxHealth,
		true
	)
end

return MonsterUpgradeCoordinator
