local AnimationPlayer = require(script.Parent.AnimationPlayer)
local AnimationSequencePlayer = require(script.Parent.AnimationSequencePlayer)
local StableModelSpawner = require(script.Parent.StableModelSpawner)

local GodzillaService = {}

local movementTracks = setmetatable({}, { __mode = "k" })

function GodzillaService.Create(template: Model, spawnCFrame: CFrame): Model
	return StableModelSpawner.Spawn(template, spawnCFrame)
end

function GodzillaService.SetMoving(model: Model, config, isMoving: boolean): AnimationTrack?
	local movementTrack = movementTracks[model]

	if not isMoving then
		if movementTrack then
			movementTrack:Stop()
			movementTrack:Destroy()
			movementTracks[model] = nil
		end

		return nil
	end

	if movementTrack and movementTrack.IsPlaying then
		return movementTrack
	end

	if movementTrack then
		movementTrack:Destroy()
	end

	local newMovementTrack = AnimationPlayer.Play(model, config.Animations.Walk, {
		Looped = true,
		Priority = Enum.AnimationPriority.Movement,
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
