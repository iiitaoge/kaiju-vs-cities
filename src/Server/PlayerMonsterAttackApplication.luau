--[[
	职责：组装正式的服务器权威玩家怪兽攻击链路。

	输入：攻击者、自己的 SpawnPointId、TargetPlayerId 和最终落点。
	输出：命令是否被接受、Reason、CommandId 和供客户端跟随的怪兽 Model。
	内部算法：按 ID 重新解析在线目标，按当前 MonsterKey 解析全部配置，调用命令协调器；
	命令被接受后异步执行开罐、移动、建筑攻击、守方怪兽反击、死亡恢复和反向封罐。

	不负责：目标浏览、客户端落点预校验、GUI、防御塔场景发现或存档。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameAnalyticsGateway = require(script.Parent.Analytics.GameAnalyticsGateway)
local PlayerJourneyAnalyticsCoordinator = require(
	script.Parent.Analytics.PlayerJourneyAnalyticsCoordinator
)
local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local GodzillaService = require(script.Parent.GodzillaService)
local ModelMover = require(script.Parent.ModelMover)
local MonsterAttackCommandCoordinator = require(script.Parent.MonsterAttackCommandCoordinator)
local MonsterExpeditionCoordinator = require(script.Parent.MonsterExpeditionCoordinator)
local MonsterExpeditionReportService = require(script.Parent.MonsterExpeditionReportService)
local MonsterIncubatorCoordinator = require(script.Parent.MonsterIncubatorCoordinator)
local MonsterRecoveryCoordinator = require(script.Parent.MonsterRecoveryCoordinator)
local MonsterReturnCoordinator = require(script.Parent.MonsterReturnCoordinator)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterTemplateResolver = require(script.Parent.MonsterTemplateResolver)
local PlayerDefenseMonsterRuntimeCoordinator = require(
	script.Parent.PlayerDefenseMonsterRuntimeCoordinator
)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local PlayerRebirthBonusQuery = require(script.Parent.PlayerRebirthBonusQuery)
local PlayerRuntimeHouseAttackAccess = require(script.Parent.PlayerRuntimeHouseAttackAccess)
local PlayerRuntimeDefenseTowerAccess = require(script.Parent.PlayerRuntimeDefenseTowerAccess)
local WorkspacePlayerWorldAccess = require(script.Parent.WorkspacePlayerWorldAccess)
local ModelAnimationConfigs = require(ReplicatedStorage.Shared.Animation.ModelAnimationConfigs)
local MonsterAttackConfigs = require(ReplicatedStorage.Shared.Monster.MonsterAttackConfigs)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local MonsterExpeditionConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionConfigs
)
local MonsterExpeditionReportBuilder = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionReportBuilder
)
local MonsterExpeditionTimingConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionTimingConfigs
)

local PlayerMonsterAttackApplication = {}

local function scaleMovement(movement, multiplier: number)
	return {
		DesiredGap = movement.DesiredGap,
		MaxGap = movement.MaxGap,
		MoveSpeed = movement.MoveSpeed * multiplier,
		MaxTravelDuration = movement.MaxTravelDuration,
		TimingSafetyMargin = movement.TimingSafetyMargin,
		TurnDuration = movement.TurnDuration,
		WalkAnimation = movement.WalkAnimation,
	}
end

local function scaleStructureAttack(attack, multiplier: number)
	return {
		StructureDamage = attack.StructureDamage * multiplier,
		Detection = attack.Detection,
		Geometry = attack.Geometry,
		Animation = attack.Animation,
	}
end

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
	local bonuses = PlayerRebirthBonusQuery.Get(player)
	return {
		Damage = combat.Damage * bonuses.MonsterDamageMultiplier,
		AttackInterval = combat.AttackInterval,
		Movement = scaleMovement(
			combat.Movement,
			bonuses.MonsterMoveSpeedMultiplier
		),
		Animation = {
			Animations = configs.Animation.Animations,
			AttackSequence = configs.Animation.MeleeAttackSequence,
			AttackEffects = configs.Animation.AttackEffects,
			SelectionMode = combat.Animation.SelectionMode,
			HitProgress = combat.Animation.HitProgress,
			Speed = combat.Animation.Speed,
		},
	}
end

local function setCombatantMoving(
	model: Model,
	isMoving: boolean,
	moveSpeed: number?
)
	if not isMoving then
		GodzillaService.StopMoving(model)
		return
	end
	local monsterKey = model:GetAttribute("MonsterKey")
	local configs = if type(monsterKey) == "string"
		then resolveStaticConfigs(monsterKey)
		else nil
	if configs then
		GodzillaService.SetMoving(
			model,
			configs.Animation,
			isMoving,
			moveSpeed,
			configs.Expedition.Movement.WalkAnimation
		)
	end
end

local function stopCombatantMotion(model: Model)
	GodzillaMoveService.Cancel(model)
	GodzillaService.StopMoving(model)
end

local function beginRecovery(player: Player, spawnPointId: string, plotOverride: Model?)
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not record then
		return
	end
	local configs = resolveStaticConfigs(record.MonsterKey)
	if not configs then
		warn(string.format("怪兽恢复缺少配置：%s/%s", player.Name, record.MonsterKey))
		return
	end

	local recoveryPlot = plotOverride or PlayerPlotAssignmentService.GetPlot(player)
	local recovery = MonsterRecoveryCoordinator.Begin(player, spawnPointId, {
		RecoveryDuration = configs.Expedition.RecoveryDuration,
		PrepareRespawn = function()
			if not recoveryPlot then
				return { Succeeded = true, Reason = nil }
			end
			return MonsterIncubatorCoordinator.Restore(
				recoveryPlot,
				spawnPointId,
				nil,
				nil
			)
		end,
		ResolveTemplate = function(monsterKey)
			local template, _, modelScale = MonsterTemplateResolver.Resolve(monsterKey)
			return template, modelScale
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

local function beginIncubatorReturn(
	player: Player,
	spawnPointId: string,
	plotOverride: Model?
)
	local returnPlot = plotOverride or PlayerPlotAssignmentService.GetPlot(player)
	local current = MonsterRosterCoordinator.Get(player, spawnPointId)
	if current and current.Model then
		stopCombatantMotion(current.Model)
	end
	return MonsterReturnCoordinator.Begin(player, spawnPointId, {
		ExecuteReturn = function(model, spawnCFrame)
			stopCombatantMotion(model)
			if not returnPlot then
				ModelMover.Snap(model, spawnCFrame)
				return { Succeeded = true, Reason = nil }
			end
			local restored = MonsterIncubatorCoordinator.Restore(
				returnPlot,
				spawnPointId,
				model,
				spawnCFrame
			)
			if restored.Succeeded and model.Parent then
				ModelMover.Snap(model, spawnCFrame)
			end
			return restored
		end,
		OnReturned = function(_returnedPlayer, _returnedSpawnPointId, model)
			GodzillaService.StopMoving(model)
		end,
	})
end

local function ensureReturnAfterFailure(
	player: Player,
	spawnPointId: string,
	plotOverride: Model?
)
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not record
		or record.State == "IdleAtSpawn"
		or record.State == "Returning"
		or record.State == "Defeated"
		or record.State == "Recovering" then
		return
	end
	local returnResult = beginIncubatorReturn(player, spawnPointId, plotOverride)
	if not returnResult.Succeeded then
		warn(string.format(
			"攻击异常后回城失败：%s/%s (%s)",
			player.Name,
			spawnPointId,
			returnResult.Reason or "Unknown"
		))
	end
end

local function preExpeditionFailure(reason: string, cancelled: boolean)
	return {
		Succeeded = false,
		EndReason = if cancelled then "Cancelled" else "Failed",
		Reason = reason,
		DestroyedHouseIds = {},
		RewardGranted = 0,
		DefeatedDefenderMonsterIds = {},
		AttackerDefeated = false,
		TowerHitCount = 0,
		TowerDamageTaken = 0,
	}
end

-- TargetPlayerId 只用于寻址；目标在线状态、领地和落点仍由下层命令协调器重新验证。
function PlayerMonsterAttackApplication.Execute(
	attacker: Player,
	spawnPointId: string,
	targetPlayerId: number,
	entryPoint: Vector3
)
	if DefenseMonsterSlotCatalog.Get(spawnPointId) then
		return {
			Succeeded = false,
			Reason = "DefenseMonsterCannotAttack",
			CommandId = nil,
			Monster = nil,
		}
	end
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
	local bonuses = PlayerRebirthBonusQuery.Get(attacker)
	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(attacker)
	if not plot then
		return {
			Succeeded = false,
			Reason = plotReason or "PlayerHasNoPlot",
			CommandId = nil,
			Monster = record.Model,
		}
	end
	local incubatorCheck = MonsterIncubatorCoordinator.Validate(plot, spawnPointId)
	if not incubatorCheck.Succeeded then
		return {
			Succeeded = false,
			Reason = incubatorCheck.Reason or "IncubatorUnavailable",
			CommandId = nil,
			Monster = record.Model,
		}
	end

	local commandResult = MonsterAttackCommandCoordinator.Execute(
		attacker,
		spawnPointId,
		targetPlayer,
		entryPoint,
		{
			TerritoryAccess = WorkspacePlayerWorldAccess.Territory,
			StartExpedition = function(commandContext, isCancelled)
				local traceId = string.format(
					"%d:%s:%d",
					commandContext.Attacker.UserId,
					commandContext.AttackerSpawnPointId,
					commandContext.CommandId
				)
				local latest = MonsterRosterCoordinator.Get(
					commandContext.Attacker,
					commandContext.AttackerSpawnPointId
				)
				if not latest or not latest.Model then
					return preExpeditionFailure("MonsterUnavailable", false)
				end
				local released = MonsterIncubatorCoordinator.Release(
					plot,
					commandContext.AttackerSpawnPointId,
					latest.Model,
					isCancelled
				)
				if not released.Succeeded then
					return preExpeditionFailure(
						released.Reason or "IncubatorReleaseFailed",
						released.Reason == "Cancelled"
					)
				end
				local moving = MonsterRosterCoordinator.Transition(
					commandContext.Attacker,
					commandContext.AttackerSpawnPointId,
					"MovingToTarget"
				)
				if not moving.Succeeded then
					return preExpeditionFailure(
						moving.Reason or "MonsterPhaseTransitionFailed",
						false
					)
				end
				return MonsterExpeditionCoordinator.Execute(
					commandContext.Attacker,
					commandContext.Defender,
					commandContext.AttackerSpawnPointId,
					commandContext.EntryPoint,
					{
						TraceId = traceId,
						TargetRegionId = commandContext.TargetRegionId,
						HouseAccess = PlayerRuntimeHouseAttackAccess,
						ModelAnimationConfig = configs.Animation,
						MonsterAttackConfig = scaleStructureAttack(
							configs.Attack,
							bonuses.MonsterDamageMultiplier
						),
						MoveSpeed = configs.Expedition.Movement.MoveSpeed
							* bonuses.MonsterMoveSpeedMultiplier,
						MaxTravelDuration = configs.Expedition.Movement.MaxTravelDuration,
						TimingSafetyMargin = configs.Expedition.Movement.TimingSafetyMargin,
						TurnDuration = configs.Expedition.Movement.TurnDuration,
						WalkAnimation = configs.Expedition.Movement.WalkAnimation,
						RewardAmount = configs.Expedition.RewardAmount,
						MaxExpeditionDuration = MonsterExpeditionTimingConfigs.ExpeditionDuration,
						DuelResolutionDuration = MonsterExpeditionTimingConfigs.DuelResolutionDuration,
						DuelWatchdogDuration = MonsterExpeditionTimingConfigs.DuelWatchdogDuration,
						Defense = {
							TowerAccess = PlayerRuntimeDefenseTowerAccess,
						},
						ResolveCombatConfig = resolveCombatConfig,
						CombatFirstStrike = "Defender",
						SetCombatantMoving = setCombatantMoving,
						IsCancelled = isCancelled,
						OnDefeated = function(defeatedPlayer, defeatedSpawnPointId, _source)
							local defeatedRecord = MonsterRosterCoordinator.Get(
								defeatedPlayer,
								defeatedSpawnPointId
							)
							if defeatedRecord and defeatedRecord.Model then
								stopCombatantMotion(defeatedRecord.Model)
							end
							if DefenseMonsterSlotCatalog.Get(defeatedSpawnPointId) then
								local recovery = PlayerDefenseMonsterRuntimeCoordinator.BeginRecovery(
									defeatedPlayer,
									defeatedSpawnPointId
								)
								if not recovery.Succeeded then
									warn("启动防守怪兽恢复失败：", recovery.Reason)
								end
							else
								beginRecovery(
									defeatedPlayer,
									defeatedSpawnPointId,
									if defeatedPlayer == commandContext.Attacker then plot else nil
								)
							end
						end,
						OnReturnRequired = function(returnPlayer, returnSpawnPointId, _endReason)
							return beginIncubatorReturn(
								returnPlayer,
								returnSpawnPointId,
								if returnPlayer == commandContext.Attacker then plot else nil
							)
						end,
						OnDefenderReturnRequired = function(returnPlayer, returnSpawnPointId)
							return PlayerDefenseMonsterRuntimeCoordinator.ReturnToSlot(
								returnPlayer,
								returnSpawnPointId
							)
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
				if commandContext.Attacker.Parent == Players then
					GameAnalyticsGateway.LogDesign(
						commandContext.Attacker,
						string.format(
							"Gameplay:Attack:Finished:%s:%s",
							commandContext.AttackerSpawnPointId,
							report.EndReason
						),
						report.Duration,
						{
							reason = report.Reason or "None",
							monsterKey = report.MonsterKey,
						}
					)
					PlayerJourneyAnalyticsCoordinator.RecordAttackFinished(
						commandContext.Attacker,
						commandContext.Defender,
						report
					)
				end
				if commandContext.Attacker.Parent ~= Players then
					local restored = MonsterIncubatorCoordinator.Restore(
						plot,
						commandContext.AttackerSpawnPointId,
						nil,
						nil
					)
					if not restored.Succeeded then
						warn("玩家离开后罐体复位失败：", restored.Reason)
					end
					return
				end
				-- 正常路径已经是 Returning/Idle；异常或回城启动失败时再补一次兜底。
				ensureReturnAfterFailure(
					commandContext.Attacker,
					commandContext.AttackerSpawnPointId,
					plot
				)
			end,
		}
	)
	if commandResult.Succeeded then
		GameAnalyticsGateway.LogDesign(
			attacker,
			"Gameplay:Attack:Accepted:" .. spawnPointId
		)
	end
	return commandResult
end

return PlayerMonsterAttackApplication
