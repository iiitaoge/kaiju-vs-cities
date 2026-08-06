--[[
	职责：把一次现有攻击动画与模型内对应 VFX 组合成同一段表现。
	输入：怪兽、动画 ID、特效节点名、播放参数、可选目标坐标查询和命中回调。
	输出：原样返回 AttackAnimationPlayer 的播放结果。
	内部算法：动画进度驱动 VFX Session；无论完成、取消或报错都会关闭特效。
	不负责：攻击选择、伤害、奖励、目标合法性或战斗状态。
]]

local AttackAnimationPlayer = require(script.Parent.AttackAnimationPlayer)
local MonsterAttackVFXController = require(script.Parent.MonsterAttackVFXController)

local MonsterAttackPresentationPlayer = {}

export type PlayOptions = {
	EffectName: string?,
	ResolveTargetPosition: (() -> Vector3?)?,
	HitProgress: number?,
	Speed: number?,
	Priority: Enum.AnimationPriority?,
	IsCancelled: (() -> boolean)?,
}

function MonsterAttackPresentationPlayer.Play(
	model: Model,
	animationAssetId: number,
	options: PlayOptions?,
	onHit: () -> ()
): AttackAnimationPlayer.PlaybackResult
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	assert(type(options) == "table" or options == nil, "options 必须是 table 或 nil")
	assert(type(onHit) == "function", "onHit 必须是 function")
	assert(
		not options
			or options.ResolveTargetPosition == nil
			or type(options.ResolveTargetPosition) == "function",
		"ResolveTargetPosition 必须是 function 或 nil"
	)

	local session = MonsterAttackVFXController.Start(
		model,
		if options then options.EffectName else nil
	)
	local function onProgress(progress: number)
		if not session then
			return
		end
		local targetPosition = if options and options.ResolveTargetPosition
			then options.ResolveTargetPosition()
			else nil
		session.Update(progress, targetPosition)
	end

	local succeeded, playbackOrError = pcall(
		AttackAnimationPlayer.Play,
		model,
		animationAssetId,
		{
			HitProgress = if options then options.HitProgress else nil,
			Speed = if options then options.Speed else nil,
			Priority = if options then options.Priority else nil,
			IsCancelled = if options then options.IsCancelled else nil,
			OnProgress = onProgress,
		},
		onHit
	)
	if session then
		session.Stop()
	end
	if not succeeded then
		error(playbackOrError, 0)
	end
	return playbackOrError
end

return MonsterAttackPresentationPlayer
