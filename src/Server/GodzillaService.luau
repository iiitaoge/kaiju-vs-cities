local AnimationPlayer = require(script.Parent.AnimationPlayer)
local AnimationSequencePlayer = require(script.Parent.AnimationSequencePlayer)
local AnimationTrackRelease = require(script.Parent.AnimationTrackRelease)
local StableModelSpawner = require(script.Parent.StableModelSpawner)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MonsterMovementRules = require(
	ReplicatedStorage.Shared.Monster.MonsterMovementRules
)

local GodzillaService = {}

local movementTracks = setmetatable({}, { __mode = "k" })

-- 输入：怪兽模型。
-- 输出：无。
-- 内部算法：停止缓存轨道，并清理 Animator 中仍在播放的 Movement 轨道。
-- 副作用：保证取消、战斗、回罐和热同步后的旧行走动画不会继续播放。
function GodzillaService.StopMoving(model: Model)
	local cachedTrack = movementTracks[model]
	movementTracks[model] = nil
	local stoppedTracks = {}

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Animator") then
			for _, track in descendant:GetPlayingAnimationTracks() do
				if track.Priority == Enum.AnimationPriority.Movement then
					AnimationTrackRelease.Release(track)
					stoppedTracks[track] = true
				end
			end
		end
	end

	if cachedTrack and not stoppedTracks[cachedTrack] then
		AnimationTrackRelease.Release(cachedTrack)
	end
end

function GodzillaService.Create(template: Model, spawnCFrame: CFrame): Model
	return StableModelSpawner.Spawn(template, spawnCFrame)
end

function GodzillaService.SetMoving(
	model: Model,
	config,
	isMoving: boolean,
	moveSpeed: number?,
	walkAnimationConfig
): AnimationTrack?
	local movementTrack = movementTracks[model]

	if not isMoving then
		GodzillaService.StopMoving(model)
		return nil
	end

	local playbackSpeed = if moveSpeed
		then MonsterMovementRules.ResolveWalkAnimationSpeed(
			moveSpeed,
			walkAnimationConfig
		)
		else 1
	if movementTrack and movementTrack.IsPlaying then
		movementTrack:AdjustSpeed(playbackSpeed)
		return movementTrack
	end

	if movementTrack then
		movementTrack:Destroy()
	end

	local newMovementTrack = AnimationPlayer.Play(model, config.Animations.Walk, {
		Looped = true,
		Priority = Enum.AnimationPriority.Movement,
		Speed = playbackSpeed,
	})
	movementTracks[model] = newMovementTrack

	return newMovementTrack
end

function GodzillaService.PlayAttackSequence(model: Model, config)
	AnimationSequencePlayer.Play(
		model,
		config.Animations,
		config.AttackSequence,
		Enum.AnimationPriority.Action
	)
end

return GodzillaService
