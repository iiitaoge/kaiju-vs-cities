--[[
	职责：组装正式的服务器权威玩家怪兽攻击链路。

	输入：攻击者、自己的 SpawnPointId、TargetPlayerId 和最终落点。
	输出：命令是否被接受、Reason、CommandId 和供客户端跟随的怪兽 Model。
	内部算法：按 ID 重新解析在线目标，按当前 MonsterKey 解析全部配置，调用命令协调器；
	命令被接受后异步执行移动、建筑攻击、守方怪兽反击、死亡恢复和直接回出生点。

	不负责：目标浏览、客户端落点预校验、GUI、防御塔场景发现或存档。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GodzillaService = require(script.Parent.GodzillaService)
local MonsterAttackCommandCoordinator = require(script.Parent.MonsterAttackCommandCoordinator)
local MonsterExpeditionCoordinator = require(script.Parent.MonsterExpeditionCoordinator)
local MonsterExpeditionReportService = require(script.Parent.MonsterExpeditionReportService)
local MonsterRecoveryCoordinator = require(script.Parent.MonsterRecoveryCoordinator)
local MonsterReturnCoordinator = require(script.Parent.MonsterReturnCoordinator)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterTemplateResolver = require(script.Parent.MonsterTemplateResolver)
local PlayerRuntimeHouseAttackAccess = require(script.Parent.PlayerRuntimeHouseAttackAccess)
local PlayerRuntimeDefenseTowerAccess = require(script.Parent.PlayerRuntimeDefenseTowerAccess)
local WorkspacePlayerWorldAccess = require(script.Parent.WorkspacePlayerWorldAccess)
local ModelAnimationConfigs = require(ReplicatedStorage.Shared.Animation.ModelAnimationConfigs)
local MonsterAttackConfigs = require(ReplicatedStorage.Shared.Monster.MonsterAttackConfigs)
local MonsterExpeditionConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionConfigs
)
local MonsterExpeditionReportBuilder = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionReportBuilder
)

local PlayerMonsterAttackApplication = {}

local function resolveStaticConfigs(monsterKey: string)
	local animation = ModelAnimationConfigs[monsterKey]
	local attack = MonsterAttackConfigs[monsterKey]
	local expedition = MonsterExpeditionConfigs[monsterKey]
	if not animation or not attack or not expedition then
		return nil, "MonsterAttackConfigUnavailable"
	end
	return {
		Animation = animation,
		Attack = attack,
		Expedition = expedition,
	}, nil
end

local function resolveCombatConfig(player: Player, spawnPointId: string)
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not record then
		return nil
	end
	local configs = resolveStaticConfigs(record.MonsterKey)
	if not configs then
		return nil
	end
	local combat = configs.Expedition.Combat
	return {
		Damage = combat.Damage,
		AttackInterval = combat.AttackInterval,
		Movement = combat.Movement,
		Animation = {
			Animations = configs.Animation.Animations,
			AttackSequence = configs.Animation.AttackSequence,
			SelectionMode = combat.Animation.SelectionMode,
			HitProgress = combat.Animation.HitProgress,
			Speed = combat.Animation.Speed,
		},
	}
end

local function setCombatantMoving(model: Model, isMoving: boolean)
	local monsterKey = model:GetAttribute("MonsterKey")
	local animation = if type(monsterKey) == "string"
		then ModelAnimationConfigs[monsterKey]
		else nil
	if animation then
		GodzillaService.SetMoving(model, animation, isMoving)
	end
end

local function beginRecovery(player: Player, spawnPointId: string)
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not record then
		return
	end
	local configs = resolveStaticConfigs(record.MonsterKey)
	if not configs then
		warn(string.format("怪兽恢复缺少配置：%s/%s", player.Name, record.MonsterKey))
		return
	end

	local recovery = MonsterRecoveryCoordinator.Begin(player, spawnPointId, {
		RecoveryDuration = configs.Expedition.RecoveryDuration,
		ResolveTemplate = function(monsterKey)
			local template = MonsterTemplateResolver.Resolve(monsterKey)
			return template
		end,
	})
	if not recovery.Succeeded then
		warn(string.format(
			"启动怪兽恢复失败：%s/%s (%s)",
			player.Name,
			spawnPointId,
			recovery.Reason or "Unknown"
		))
	end
end

local function beginDirectReturn(player: Player, spawnPointId: string)
	return MonsterReturnCoordinator.Begin(player, spawnPointId, {
		ExecuteReturn = function(model, spawnCFrame)
			model:PivotTo(spawnCFrame)
			return { Succeeded = true, Reason = nil }
		end,
	})
end

local function ensureReturnAfterFailure(player: Player, spawnPointId: string)
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not record
		or record.State == "IdleAtSpawn"
		or record.State == "Returning"
		or record.State == "Defeated"
		or record.State == "Recovering" then
		return
	end
	local returnResult = beginDirectReturn(player, spawnPointId)
	if not returnResult.Succeeded then
		warn(string.format(
			"攻击异常后回城失败：%s/%s (%s)",
			player.Name,
			spawnPointId,
			returnResult.Reason or "Unknown"
		))
	end
end

-- TargetPlayerId 只用于寻址；目标在线状态、领地和落点仍由下层命令协调器重新验证。
function PlayerMonsterAttackApplication.Execute(
	attacker: Player,
	spawnPointId: string,
	targetPlayerId: number,
	entryPoint: Vector3
)
	local targetPlayer = Players:GetPlayerByUserId(targetPlayerId)
	if not targetPlayer then
		return {
			Succeeded = false,
			Reason = "TargetPlayerUnavailable",
			CommandId = nil,
			Monster = nil,
		}
	end

	local record = MonsterRosterCoordinator.Get(attacker, spawnPointId)
	if not record then
		return {
			Succeeded = false,
			Reason = "MonsterUnavailable",
			CommandId = nil,
			Monster = nil,
		}
	end
	local configs, configReason = resolveStaticConfigs(record.MonsterKey)
	if not configs then
		return {
			Succeeded = false,
			Reason = configReason,
			CommandId = nil,
			Monster = record.Model,
		}
	end
	local monsterKey = record.MonsterKey

	return MonsterAttackCommandCoordinator.Execute(
		attacker,
		spawnPointId,
		targetPlayer,
		entryPoint,
		{
			TerritoryAccess = WorkspacePlayerWorldAccess.Territory,
			StartExpedition = function(commandContext, isCancelled)
				return MonsterExpeditionCoordinator.Execute(
					commandContext.Attacker,
					commandContext.Defender,
					commandContext.AttackerSpawnPointId,
					commandContext.EntryPoint,
					{
						HouseAccess = PlayerRuntimeHouseAttackAccess,
						ModelAnimationConfig = configs.Animation,
						MonsterAttackConfig = configs.Attack,
						MoveSpeed = configs.Expedition.Movement.MoveSpeed,
						TurnDuration = configs.Expedition.Movement.TurnDuration,
						RewardAmount = configs.Expedition.RewardAmount,
						Defense = {
							TowerAccess = PlayerRuntimeDefenseTowerAccess,
							DefenderDetectionRadius = configs.Expedition.Defense.DefenderDetectionRadius,
						},
						ResolveCombatConfig = resolveCombatConfig,
						CombatFirstStrike = "Defender",
						SetCombatantMoving = setCombatantMoving,
						IsCancelled = isCancelled,
						OnDefeated = function(defeatedPlayer, defeatedSpawnPointId, _source)
							beginRecovery(defeatedPlayer, defeatedSpawnPointId)
						end,
						OnReturnRequired = function(returnPlayer, returnSpawnPointId, _endReason)
							return beginDirectReturn(returnPlayer, returnSpawnPointId)
						end,
					}
				)
			end,
			OnCommandFinished = function(
				commandContext,
				callSucceeded,
				result
			)
				local report = MonsterExpeditionReportBuilder.Build({
					CommandId = commandContext.CommandId,
					AttackerUserId = commandContext.Attacker.UserId,
					DefenderUserId = commandContext.Defender.UserId,
					AttackerSpawnPointId = commandContext.AttackerSpawnPointId,
					MonsterKey = monsterKey,
					EntryPoint = commandContext.EntryPoint,
					StartedAt = commandContext.StartedAt,
				}, callSucceeded, result, workspace:GetServerTimeNow())
				MonsterExpeditionReportService.Store(commandContext.Attacker, report)
				-- 正常路径已经是 Returning/Idle；异常或回城启动失败时再补一次兜底。
				ensureReturnAfterFailure(
					commandContext.Attacker,
					commandContext.AttackerSpawnPointId
				)
			end,
		}
	)
end

return PlayerMonsterAttackApplication
