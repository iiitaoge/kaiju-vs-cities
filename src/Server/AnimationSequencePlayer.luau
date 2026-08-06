local AnimationPlayer = require(script.Parent.AnimationPlayer)
local AnimationTrackRelease = require(script.Parent.AnimationTrackRelease)

local AnimationSequencePlayer = {}

function AnimationSequencePlayer.Play(
	model: Model,
	animationIds: { [string]: number },
	sequence: { string },
	priority: Enum.AnimationPriority
)
	for _, animationName in sequence do
		local animationAssetId = assert(animationIds[animationName], string.format("未知的动画：%s", animationName))
		local track = AnimationPlayer.Play(model, animationAssetId, {
			Looped = false,
			Priority = priority,
		})

		AnimationTrackRelease.WaitForCompletion(track)
	end
end

return AnimationSequencePlayer
