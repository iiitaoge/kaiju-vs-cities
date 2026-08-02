local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterHealthRules = require(ReplicatedStorage.Shared.Monster.MonsterHealthRules)
local MonsterStateRules = require(ReplicatedStorage.Shared.Monster.MonsterStateRules)

local MonsterDamageCoordinator = {}

export type DamageSource = {
	OwnerUserId: number,
	SourceId: string,
	Kind: "DefenseTower" | "Monster",
}

export type ApplyOptions = {
	OnDefeated: ((Player, string, DamageSource) -> ())?,
}

-- 输入：目标玩家、目标出生点、服务器伤害来源和伤害值。
-- 输出：生命值变化、死亡状态和明确失败原因。
-- 内部算法：验证敌我和可受伤状态，调用纯生命规则，再同步状态与运行时模型。
function MonsterDamageCoordinator.ApplyDamage(
	targetPlayer: Player,
	targetSpawnPointId: string,
	source: DamageSource,
	damage: number,
	options: ApplyOptions?
)
	local current = MonsterRosterCoordinator.Get(targetPlayer, targetSpawnPointId)
	if not current then
		return {
			Succeeded = false,
			Reason = "UnknownTargetMonster",
			DamageApplied = 0,
			RemainingHealth = 0,
			Defeated = false,
		}
	end
	if type(source) ~= "table"
		or type(source.OwnerUserId) ~= "number"
		or type(source.SourceId) ~= "string" then
		return {
			Succeeded = false,
			Reason = "InvalidDamageSource",
			DamageApplied = 0,
			RemainingHealth = current.Health,
			Defeated = false,
		}
	end
	if source.OwnerUserId == targetPlayer.UserId then
		return {
			Succeeded = false,
			Reason = "FriendlyFire",
			DamageApplied = 0,
			RemainingHealth = current.Health,
			Defeated = false,
		}
	end
	if not MonsterStateRules.IsDamageable(current.State) then
		return {
			Succeeded = false,
			Reason = "MonsterNotDamageable",
			DamageApplied = 0,
			RemainingHealth = current.Health,
			Defeated = current.State == "Defeated" or current.State == "Recovering",
		}
	end

	local calculation = MonsterHealthRules.ApplyDamage(
		current.Health,
		current.MaxHealth,
		damage
	)
	if not calculation.Succeeded then
		return calculation
	end

	local healthWrite = MonsterRosterCoordinator.SetHealth(
		targetPlayer,
		targetSpawnPointId,
		calculation.RemainingHealth
	)
	if not healthWrite.Succeeded then
		return {
			Succeeded = false,
			Reason = healthWrite.Reason or "HealthWriteFailed",
			DamageApplied = 0,
			RemainingHealth = current.Health,
			Defeated = false,
		}
	end

	if calculation.Defeated then
		local transition = MonsterRosterCoordinator.Transition(
			targetPlayer,
			targetSpawnPointId,
			"Defeated"
		)
		if not transition.Succeeded then
			return {
				Succeeded = false,
				Reason = transition.Reason or "DefeatTransitionFailed",
				DamageApplied = calculation.DamageApplied,
				RemainingHealth = calculation.RemainingHealth,
				Defeated = false,
			}
		end
		MonsterRosterCoordinator.DestroyRuntimeModel(targetPlayer, targetSpawnPointId)

		if options and options.OnDefeated then
			local callbackSucceeded, callbackError = pcall(
				options.OnDefeated,
				targetPlayer,
				targetSpawnPointId,
				source
			)
			if not callbackSucceeded then
				warn("怪兽死亡回调失败：", callbackError)
			end
		end
	end

	return {
		Succeeded = true,
		Reason = nil,
		DamageApplied = calculation.DamageApplied,
		RemainingHealth = calculation.RemainingHealth,
		Defeated = calculation.Defeated,
	}
end

return MonsterDamageCoordinator
