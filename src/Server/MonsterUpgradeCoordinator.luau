local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterStateRules = require(ReplicatedStorage.Shared.Monster.MonsterStateRules)

local MonsterUpgradeCoordinator = {}

-- 输入：升级逻辑已确定的新怪兽身份、模板和最大生命。
-- 输出：是否完成出生点怪兽替换，以及替换后的记录。
-- 内部算法：验证出生点存在和怪兽空闲，再把原子替换交给名册协调器。
-- 不负责：价格、建筑等级、升级条件和配置映射。
function MonsterUpgradeCoordinator.Execute(
	player: Player,
	spawnPointId: string,
	newMonsterKey: string,
	template: Model,
	spawnPoint: BasePart,
	maxHealth: number
)
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

	return MonsterRosterCoordinator.ReplaceForSpawnPoint(
		player,
		spawnPointId,
		newMonsterKey,
		template,
		spawnPoint,
		maxHealth
	)
end

return MonsterUpgradeCoordinator
