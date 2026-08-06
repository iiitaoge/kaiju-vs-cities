local RunService = game:GetService("RunService")

local AnimationPlayer = require(script.Parent.AnimationPlayer)
local AnimationTrackRelease = require(script.Parent.AnimationTrackRelease)

local AttackAnimationPlayer = {}

local DEFAULT_HIT_PROGRESS = 0.65
local DEFAULT_SPEED = 1

export type PlayOptions = {
	-- 0 到 1 的归一化命中进度；nil 时使用 0.65。
	HitProgress: number?,
	-- 播放速度倍率；nil 时使用 1。
	Speed: number?,
	-- 攻击动画优先级；nil 时使用 Action。
	Priority: Enum.AnimationPriority?,
	-- 每帧调用；返回 true 时立即停止动画且不再触发尚未发生的命中。
	IsCancelled: (() -> boolean)?,
	-- 动画开始时以 0 调用，随后按播放进度调用；只负责同步表现。
	OnProgress: ((number) -> ())?,
}

export type PlaybackResult = {
	-- onHit 是否已被调用。
	HitTriggered: boolean,
	-- 动画是否自然播放到结束附近，而不是被提前停止。
	Completed: boolean,
	-- 是否由 IsCancelled 主动取消。
	Cancelled: boolean,
}

-- 输入：
--   model：播放攻击动画的怪兽模型。
--   animationAssetId：攻击动画数字资源 ID。
--   options：可选的命中进度、速度、优先级和显式取消查询。
--   onHit：到达命中进度时执行一次的显式回调；房屋结算由调用者放入该回调。
-- 输出：
--   HitTriggered 表示是否触发命中；Completed 表示是否自然播放完成；
--   Cancelled 表示是否由 IsCancelled 主动停止。
-- 副作用：立即播放攻击动画；函数返回前会销毁内部 AnimationTrack。
function AttackAnimationPlayer.Play(
	model: Model,
	animationAssetId: number,
	options: PlayOptions?,
	onHit: () -> ()
): PlaybackResult
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(
		type(animationAssetId) == "number" and animationAssetId > 0,
		"animationAssetId 必须是大于 0 的 number"
	)
	assert(options == nil or type(options) == "table", "options 必须是 table 或 nil")
	assert(type(onHit) == "function", "onHit 必须是 function")
	assert(
		not options
			or options.IsCancelled == nil
			or type(options.IsCancelled) == "function",
		"IsCancelled 必须是 function 或 nil"
	)
	assert(
		not options
			or options.OnProgress == nil
			or type(options.OnProgress) == "function",
		"OnProgress 必须是 function 或 nil"
	)

	local hitProgress = if options and options.HitProgress ~= nil
		then options.HitProgress
		else DEFAULT_HIT_PROGRESS
	local speed = if options and options.Speed ~= nil then options.Speed else DEFAULT_SPEED
	local priority = if options and options.Priority
		then options.Priority
		else Enum.AnimationPriority.Action

	assert(
		type(hitProgress) == "number" and hitProgress >= 0 and hitProgress <= 1,
		"HitProgress 必须在 0 到 1 之间"
	)
	assert(type(speed) == "number" and speed > 0, "Speed 必须是大于 0 的 number")

	local track = AnimationPlayer.Play(model, animationAssetId, {
		Looped = false,
		Priority = priority,
		Speed = speed,
	})
	local hitTriggered = false
	local completed = false
	local cancelled = false
	local released = false

	local function releaseTrack()
		if released then
			return
		end
		released = true
		AnimationTrackRelease.Release(track)
	end

	local function notifyProgress(progress: number)
		if not options or not options.OnProgress then
			return
		end
		local succeeded, message = pcall(options.OnProgress, progress)
		if not succeeded then
			releaseTrack()
			error(message, 0)
		end
	end

	local function checkCancelled(): boolean
		if not options or not options.IsCancelled then
			return false
		end

		local succeeded, result = pcall(options.IsCancelled)
		if not succeeded then
			releaseTrack()
			error(result, 0)
		end
		if result then
			cancelled = true
			releaseTrack()
			return true
		end

		return false
	end

	local function triggerHit()
		if hitTriggered then
			return
		end

		hitTriggered = true
		local succeeded, message = pcall(onHit)
		if not succeeded then
			releaseTrack()
			error(message, 0)
		end
	end

	notifyProgress(0)

	while track.IsPlaying do
		if checkCancelled() then
			break
		end

		local length = track.Length
		if length > 0 then
			local progress = math.clamp(track.TimePosition / length, 0, 1)
			notifyProgress(progress)
			if not hitTriggered and progress >= hitProgress then
				triggerHit()
			end
			if hitTriggered
				and (length - track.TimePosition) / speed
					<= AnimationTrackRelease.DefaultFadeDuration
			then
				completed = true
				break
			end
		end

		if track.IsPlaying then
			RunService.Heartbeat:Wait()
		end
	end

	local length = track.Length
	if not cancelled and length > 0 then
		local finalProgress = math.clamp(track.TimePosition / length, 0, 1)
		notifyProgress(finalProgress)
		if not hitTriggered and finalProgress >= hitProgress then
			triggerHit()
		end
		if finalProgress >= 1 - 1 / 30 / length then
			completed = true
		end
	end

	releaseTrack()
	return {
		HitTriggered = hitTriggered,
		Completed = completed,
		Cancelled = cancelled,
	}
end

return AttackAnimationPlayer
