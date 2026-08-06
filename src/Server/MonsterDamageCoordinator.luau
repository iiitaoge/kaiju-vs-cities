local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterCombatDiagnosticLog = require(script.Parent.MonsterCombatDiagnosticLog)
local MonsterHealthRules = require(ReplicatedStorage.Shared.Monster.MonsterHealthRules)
local MonsterStateRules = require(ReplicatedStorage.Shared.Monster.MonsterStateRules)

local MonsterDamageCoordinator = {}

export type DamageSource = {
	OwnerUserId: number,
	SourceId: string,
	Kind: "DefenseTower" | "Monster",
	TraceId: string?,
}

export type ApplyOptions = {
	-- 在死亡状态写入后、运行时模型销毁前调用，供上层终止移动/动画并启动恢复。
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
	local traceId = if type(source) == "table" and type(source.TraceId) == "string"
		then source.TraceId
		else nil
	local function emit(result)
		if traceId then
			MonsterCombatDiagnosticLog.Emit("MONSTER_DAMAGE", {
				TraceId = traceId,
				SourceKind = if type(source) == "table" then tostring(source.Kind) else "Invalid",
				SourceOwnerUserId = if type(source) == "table" then source.OwnerUserId else 0,
				SourceId = if type(source) == "table" then tostring(source.SourceId) else "Invalid",
				TargetUserId = targetPlayer.UserId,
				TargetSpawnPointId = targetSpawnPointId,
				TargetMonsterKey = if current then current.MonsterKey else "None",
				StateBefore = if current then current.State else "None",
				RequestedDamage = damage,
				PreviousHealth = if current then current.Health else 0,
				DamageApplied = result.DamageApplied,
				RemainingHealth = result.RemainingHealth,
				Defeated = result.Defeated,
				Succeeded = result.Succeeded,
				Reason = result.Reason or "None",
			})
		end
		return result
	end
	if not current then
		return emit({
			Succeeded = false,
			Reason = "UnknownTargetMonster",
			DamageApplied = 0,
			RemainingHealth = 0,
			Defeated = false,
		})
	end
	if type(source) ~= "table"
		or type(source.OwnerUserId) ~= "number"
		or type(source.SourceId) ~= "string" then
		return emit({
			Succeeded = false,
			Reason = "InvalidDamageSource",
			DamageApplied = 0,
			RemainingHealth = current.Health,
			Defeated = false,
		})
	end
	if source.OwnerUserId == targetPlayer.UserId then
		return emit({
			Succeeded = false,
			Reason = "FriendlyFire",
			DamageApplied = 0,
			RemainingHealth = current.Health,
			Defeated = false,
		})
	end
	if not MonsterStateRules.IsDamageable(current.State) then
		return emit({
			Succeeded = false,
			Reason = "MonsterNotDamageable",
			DamageApplied = 0,
			RemainingHealth = current.Health,
			Defeated = current.State == "Defeated" or current.State == "Recovering",
		})
	end

	local calculation = MonsterHealthRules.ApplyDamage(
		current.Health,
		current.MaxHealth,
		damage
	)
	if not calculation.Succeeded then
		return emit(calculation)
	end

	local healthWrite = MonsterRosterCoordinator.SetHealth(
		targetPlayer,
		targetSpawnPointId,
		calculation.RemainingHealth
	)
	if not healthWrite.Succeeded then
		return emit({
			Succeeded = false,
			Reason = healthWrite.Reason or "HealthWriteFailed",
			DamageApplied = 0,
			RemainingHealth = current.Health,
			Defeated = false,
		})
	end

	if calculation.Defeated then
		local transition = MonsterRosterCoordinator.Transition(
			targetPlayer,
			targetSpawnPointId,
			"Defeated"
		)
		if not transition.Succeeded then
			return emit({
				Succeeded = false,
				Reason = transition.Reason or "DefeatTransitionFailed",
				DamageApplied = calculation.DamageApplied,
				RemainingHealth = calculation.RemainingHealth,
				Defeated = false,
			})
		end
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

		MonsterRosterCoordinator.DestroyRuntimeModel(targetPlayer, targetSpawnPointId)
	end

	return emit({
		Succeeded = true,
		Reason = nil,
		DamageApplied = calculation.DamageApplied,
		RemainingHealth = calculation.RemainingHealth,
		Defeated = calculation.Defeated,
	})
end

return MonsterDamageCoordinator
