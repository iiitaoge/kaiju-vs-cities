--[[
	职责：统一释放服务器播放的 AnimationTrack，并让 Animator 把骨骼混回默认姿势。
	输入：轨道和可选淡出时长；WaitForCompletion 负责在自然结束前进入淡出窗口。
	输出：无；返回时轨道已销毁且默认淡出时长已经经过。
	内部算法：仍在播放时 Stop(fade) → 等待权重归零 → Destroy。
	不负责：创建轨道、选择动画、命中时机、VFX 或移动状态。
]]

local RunService = game:GetService("RunService")

local AnimationTrackRelease = {}

AnimationTrackRelease.DefaultFadeDuration = 0.1

local function resolveFadeDuration(fadeDuration: number?): number
	local resolved = if fadeDuration == nil
		then AnimationTrackRelease.DefaultFadeDuration
		else fadeDuration
	assert(type(resolved) == "number" and resolved >= 0, "fadeDuration 必须是非负数")
	return resolved
end

function AnimationTrackRelease.Release(track: AnimationTrack, fadeDuration: number?)
	assert(track:IsA("AnimationTrack"), "track 必须是 AnimationTrack")
	local resolvedFadeDuration = resolveFadeDuration(fadeDuration)
	if track.IsPlaying then
		track:Stop(resolvedFadeDuration)
		if resolvedFadeDuration > 0 then
			task.wait(resolvedFadeDuration)
		end
	end
	track:Destroy()
end

function AnimationTrackRelease.WaitForCompletion(
	track: AnimationTrack,
	fadeDuration: number?
)
	assert(track:IsA("AnimationTrack"), "track 必须是 AnimationTrack")
	local resolvedFadeDuration = resolveFadeDuration(fadeDuration)
	while track.IsPlaying do
		local length = track.Length
		local speed = math.abs(track.Speed)
		if length > 0
			and speed > 0
			and (length - track.TimePosition) / speed <= resolvedFadeDuration
		then
			break
		end
		RunService.Heartbeat:Wait()
	end
	AnimationTrackRelease.Release(track, resolvedFadeDuration)
end

return table.freeze(AnimationTrackRelease)
