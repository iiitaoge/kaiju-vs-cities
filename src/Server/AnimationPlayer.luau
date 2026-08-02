local AnimationPlayer = {}

export type PlayOptions = {
	-- 是否循环播放；nil 时保留 AnimationTrack 默认值。
	Looped: boolean?,
	-- 动画优先级；nil 时保留 AnimationTrack 默认值。
	Priority: Enum.AnimationPriority?,
	-- 播放速度倍率；nil 时使用 1。
	Speed: number?,
}

-- 输入：
--   model：包含 Animator 的模型。
--   animationAssetId：不带 rbxassetid:// 前缀的动画资源数字 ID。
--   options：可选的循环、优先级和速度参数。
-- 输出：
--   已经开始播放的 AnimationTrack；调用者负责停止和销毁。
-- 副作用：在模型 Animator 上立即加载并播放动画。
function AnimationPlayer.Play(model: Model, animationAssetId: number, options: PlayOptions?): AnimationTrack
	local animator = assert(model:FindFirstChildWhichIsA("Animator", true), "模型中找不到 Animator")
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. animationAssetId

	local track = animator:LoadAnimation(animation)
	animation:Destroy()

	if options then
		if options.Looped ~= nil then
			track.Looped = options.Looped
		end

		if options.Priority then
			track.Priority = options.Priority
		end
	end

	track:Play()
	if options and options.Speed ~= nil then
		assert(type(options.Speed) == "number" and options.Speed > 0, "Speed 必须是大于 0 的 number")
		track:AdjustSpeed(options.Speed)
	end

	return track
end

return AnimationPlayer
