--[[
	职责：组装服务器权威的单人固定演示出征链路。
	输入：在线玩家、自己的 SpawnPointId、R1/R2 可攻击区域内落点。
	输出：命令是否接受、Reason、CommandId 和供客户端跟随的怪兽 Model。
	内部算法：调用单人命令协调器；接受后开罐、运镜、移动到点击点，
		复用多人模式的持续激光和 HouseAttackCommitter 扣血流程，最后回城。
	不负责：目标选择、玩家 Plot、玩家存档、客户端选点或攻击奖励。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GodzillaMoveService = require(script.Parent.GodzillaMoveService)
local GodzillaService = require(script.Parent.GodzillaService)
local ModelMover = require(script.Parent.ModelMover)
local MonsterAttackCameraPublisher = require(script.Parent.MonsterAttackCameraPublisher)
local MonsterIncubatorCoordinator = require(script.Parent.MonsterIncubatorCoordinator)
local MonsterReturnCoordinator = require(script.Parent.MonsterReturnCoordinator)
local MonsterRosterCoordinator = require(script.Parent.MonsterRosterCoordinator)
local MonsterStructureLaserCoordinator = require(
	script.Parent.MonsterStructureLaserCoordinator
)
local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local PlayerRebirthBonusQuery = require(script.Parent.PlayerRebirthBonusQuery)
local SoloShowcaseHouseAttackAccess = require(
	script.Parent.SoloShowcaseHouseAttackAccess
)
local SoloShowcaseRuntimeService = require(script.Parent.SoloShowcaseRuntimeService)
local SoloMonsterAttackCommandCoordinator = require(
	script.Parent.SoloMonsterAttackCommandCoordinator
)
local WorkspaceSoloAttackAreaAccess = require(script.Parent.WorkspaceSoloAttackAreaAccess)
local ModelAnimationConfigs = require(ReplicatedStorage.Shared.Animation.ModelAnimationConfigs)
local MonsterAttackSelectionConfig = require(
	ReplicatedStorage.Shared.Monster.MonsterAttackSelectionConfig
)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)
local MonsterAttackConfigs = require(ReplicatedStorage.Shared.Monster.MonsterAttackConfigs)
local MonsterExpeditionConfigs = require(
	ReplicatedStorage.Shared.Monster.MonsterExpeditionConfigs
)
local SoloMonsterAttackConfigs = require(
	ReplicatedStorage.Shared.Monster.SoloMonsterAttackConfigs
)

local PlayerSoloMonsterAttackApplication = {}

local function result(succeeded: boolean, reason: string?)
	return {
		Succeeded = succeeded,
		Reason = reason,
	}
end

local function resolveConfigs(monsterKey: string)
	local animation = ModelAnimationConfigs[monsterKey]
	local attack = MonsterAttackConfigs[monsterKey]
	local expedition = MonsterExpeditionConfigs[monsterKey]
	if not animation or not attack or not expedition then
		return nil
	end
	return {
		Animation = animation,
		Attack = attack,
		Expedition = expedition,
	}
end

local function stopMotion(model: Model)
	GodzillaMoveService.Cancel(model)
	GodzillaService.StopMoving(model)
end

local function beginReturn(player: Player, spawnPointId: string, plot: Model)
	local current = MonsterRosterCoordinator.Get(player, spawnPointId)
	if current and current.Model then
		stopMotion(current.Model)
	end
	return MonsterReturnCoordinator.Begin(player, spawnPointId, {
		ExecuteReturn = function(model, spawnCFrame)
			stopMotion(model)
			local restored = MonsterIncubatorCoordinator.Restore(
				plot,
				spawnPointId,
				model,
				spawnCFrame
			)
			if restored.Succeeded and model.Parent then
				ModelMover.Snap(model, spawnCFrame)
			end
			return restored
		end,
		OnReturned = function(_player, _spawnPointId, model)
			GodzillaService.StopMoving(model)
		end,
	})
end

local function ensureReturn(player: Player, spawnPointId: string, plot: Model)
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not record
		or record.State == "IdleAtSpawn"
		or record.State == "Returning"
		or record.State == "Defeated"
		or record.State == "Recovering" then
		return
	end
	local returned = beginReturn(player, spawnPointId, plot)
	if not returned.Succeeded then
		warn("单人出征兜底回城失败：", returned.Reason)
	end
end

local function playStructureAttack(
	player: Player,
	monster: Model,
	targetPosition: Vector3,
	targetRegionId: string,
	configs,
	isCancelled: () -> boolean
)
	return MonsterStructureLaserCoordinator.Execute(
		player,
		monster,
		targetPosition,
		{
			TargetRegionId = targetRegionId,
			HouseAccess = SoloShowcaseHouseAttackAccess,
			ModelAnimationConfig = configs.Animation,
			MonsterAttackConfig = configs.Attack,
			TurnDuration = configs.Expedition.Movement.TurnDuration,
			RewardAmount = SoloMonsterAttackConfigs.RewardAmount,
			RewardPlayer = player,
			PollStopReason = function()
				return if isCancelled() then "Cancelled" else nil
			end,
		}
	)
end

function PlayerSoloMonsterAttackApplication.Execute(
	player: Player,
	spawnPointId: string,
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
	local record = MonsterRosterCoordinator.Get(player, spawnPointId)
	if not record then
		return {
			Succeeded = false,
			Reason = "MonsterUnavailable",
			CommandId = nil,
			Monster = nil,
		}
	end
	local configs = resolveConfigs(record.MonsterKey)
	if not configs then
		return {
			Succeeded = false,
			Reason = "MonsterAttackConfigUnavailable",
			CommandId = nil,
			Monster = record.Model,
		}
	end
	local plot, plotReason = PlayerPlotAssignmentService.GetPlot(player)
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

	local movement = configs.Expedition.Movement
	local moveSpeed = movement.MoveSpeed
		* PlayerRebirthBonusQuery.Get(player).MonsterMoveSpeedMultiplier
	return SoloMonsterAttackCommandCoordinator.Execute(
		player,
		spawnPointId,
		entryPoint,
		{
			AreaAccess = WorkspaceSoloAttackAreaAccess,
			PrepareAttack = SoloShowcaseRuntimeService.Reset,
			StartExpedition = function(context, isCancelled)
				local latest = MonsterRosterCoordinator.Get(
					context.Player,
					context.SpawnPointId
				)
				if not latest or not latest.Model then
					return result(false, "MonsterUnavailable")
				end
				local released = MonsterIncubatorCoordinator.Release(
					plot,
					context.SpawnPointId,
					latest.Model,
					isCancelled
				)
				if not released.Succeeded then
					return result(false, released.Reason or "IncubatorReleaseFailed")
				end
				local targetPlotName, regionId, cameraReason =
					WorkspaceSoloAttackAreaAccess.ResolveCameraTarget(
						context.TargetPlotName,
						context.EntryPoint
					)
				if not targetPlotName or not regionId then
					return result(false, cameraReason or "RegionCameraTargetUnavailable")
				end
				if regionId ~= context.TargetRegionId then
					return result(false, "SoloAttackRegionChanged")
				end
				local cameraPublished = MonsterAttackCameraPublisher.Publish(
					context.Player,
					{
						Kind = "FocusSoloRegion",
						CommandId = context.CommandId,
						AttackerUserId = context.Player.UserId,
						AttackerSpawnPointId = context.SpawnPointId,
						TargetPlotName = targetPlotName,
						RegionId = regionId or SoloMonsterAttackConfigs.CameraFallbackRegionId,
					}
				)
				if not cameraPublished.Succeeded then
					return result(
						false,
						cameraPublished.Reason or "RegionCameraPublishFailed"
					)
				end
				local cameraReady = MonsterAttackCameraPublisher.WaitForCompletion(
					context.Player,
					context.SpawnPointId,
					context.CommandId,
					MonsterAttackSelectionConfig.MarkerCamera.CompletionTimeout,
					isCancelled
				)
				if not cameraReady.Succeeded then
					return result(
						false,
						cameraReady.Reason or "RegionCameraTransitionFailed"
					)
				end
				local moving = MonsterRosterCoordinator.Transition(
					context.Player,
					context.SpawnPointId,
					"MovingToTarget"
				)
				if not moving.Succeeded or not moving.Record or not moving.Record.Model then
					return result(false, moving.Reason or "MonsterPhaseTransitionFailed")
				end
				local model = moving.Record.Model
				local moved = GodzillaMoveService.MoveTo(model, context.EntryPoint, {
					MoveSpeed = moveSpeed,
					MaxTravelDuration = movement.MaxTravelDuration,
					TimingSafetyMargin = movement.TimingSafetyMargin,
					TurnDuration = movement.TurnDuration,
					SetMoving = function(isMoving, effectiveSpeed)
						GodzillaService.SetMoving(
							model,
							configs.Animation,
							isMoving,
							effectiveSpeed,
							movement.WalkAnimation
						)
					end,
				})
				if not moved then
					return result(false, if isCancelled() then "Cancelled" else "MoveFailed")
				end
				if isCancelled() then
					return result(false, "Cancelled")
				end
				return playStructureAttack(
					context.Player,
					model,
					context.EntryPoint,
					context.TargetRegionId,
					configs,
					isCancelled
				)
			end,
			OnCommandFinished = function(context, callSucceeded, expeditionResult)
				if not callSucceeded then
					warn("单人出征执行异常：", expeditionResult)
				elseif type(expeditionResult) == "table"
					and not expeditionResult.Succeeded
					and expeditionResult.Reason ~= "Cancelled" then
					warn("单人出征提前结束：", expeditionResult.Reason)
				end
				if context.Player.Parent ~= Players then
					local restored = MonsterIncubatorCoordinator.Restore(
						plot,
						context.SpawnPointId,
						nil,
						nil
					)
					if not restored.Succeeded then
						warn("单人玩家离开后罐体复位失败：", restored.Reason)
					end
					return
				end
				ensureReturn(context.Player, context.SpawnPointId, plot)
			end,
		}
	)
end

return PlayerSoloMonsterAttackApplication
