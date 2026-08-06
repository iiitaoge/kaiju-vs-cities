--[[
	职责：播放一次原子吐息蓄力，并把动画和激光保持在喷射状态直到显式停止。
	输入：怪兽、动画/特效、初始终点、保持进度、播放速度和可选取消查询。
	输出：可连续更新终点并停止的 Session；蓄力未完成时返回稳定 Reason。
	内部算法：播放一次 AtomicAttack → 到达喷射进度后冻结 AnimationTrack → Hold VFX。
	不负责：选择房屋、转向、伤害、奖励或出征时限。
]]

local RunService = game:GetService("RunService")

local AnimationPlayer = require(script.Parent.AnimationPlayer)
local AnimationTrackRelease = require(script.Parent.AnimationTrackRelease)
local MonsterAttackVFXController = require(script.Parent.MonsterAttackVFXController)

local ContinuousAtomicLaserPresentation = {}

export type StartOptions = {
	HoldProgress: number,
	Speed: number,
	IsCancelled: (() -> boolean)?,
}

export type Session = {
	UpdateTarget: (Vector3) -> (),
	Stop: () -> (),
}

function ContinuousAtomicLaserPresentation.Start(
	model: Model,
	animationAssetId: number,
	effectName: string,
	initialTargetPosition: Vector3,
	options: StartOptions
): (Session?, string?)
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(type(animationAssetId) == "number" and animationAssetId > 0, "animationAssetId 无效")
	assert(type(effectName) == "string" and effectName ~= "", "effectName 无效")
	assert(typeof(initialTargetPosition) == "Vector3", "initialTargetPosition 无效")
	assert(type(options) == "table", "options 必须是 table")
	assert(
		type(options.HoldProgress) == "number"
			and options.HoldProgress > 0
			and options.HoldProgress < 1,
		"HoldProgress 必须在 0 和 1 之间"
	)
	assert(type(options.Speed) == "number" and options.Speed > 0, "Speed 必须大于 0")
	assert(
		options.IsCancelled == nil or type(options.IsCancelled) == "function",
		"IsCancelled 无效"
	)

	local vfxSession = MonsterAttackVFXController.Start(model, effectName)
	if not vfxSession then
		return nil, "AtomicAttackEffectUnavailable"
	end
	local track = AnimationPlayer.Play(model, animationAssetId, {
		Looped = false,
		Priority = Enum.AnimationPriority.Action,
		Speed = options.Speed,
	})
	local stopped = false
	local targetPosition = initialTargetPosition

	local function stop()
		if stopped then
			return
		end
		stopped = true
		vfxSession.Stop()
		AnimationTrackRelease.Release(track)
	end

	while track.IsPlaying do
		if options.IsCancelled then
			local succeeded, cancelledOrError = pcall(options.IsCancelled)
			if not succeeded then
				stop()
				error(cancelledOrError, 0)
			end
			if cancelledOrError then
				stop()
				return nil, "Cancelled"
			end
		end
		local length = track.Length
		if length > 0 then
			local progress = math.clamp(track.TimePosition / length, 0, 1)
			vfxSession.Update(progress, targetPosition)
			if progress >= options.HoldProgress then
				track.TimePosition = length * options.HoldProgress
				track:AdjustSpeed(0)
				vfxSession.Hold(targetPosition)
				return {
					UpdateTarget = function(nextTargetPosition: Vector3)
						assert(typeof(nextTargetPosition) == "Vector3", "nextTargetPosition 无效")
						if stopped then
							return
						end
						targetPosition = nextTargetPosition
						vfxSession.Hold(targetPosition)
					end,
					Stop = stop,
				}, nil
			end
		end
		RunService.Heartbeat:Wait()
	end

	stop()
	return nil, "AtomicAttackAnimationInterrupted"
end

return ContinuousAtomicLaserPresentation
