--[[
	职责：控制怪兽模型内已有攻击特效的启停、激光发射点与终点。
	输入：怪兽 Model、VFX 节点名、归一化动画进度和可选目标世界坐标。
	输出：可更新、可停止的短生命周期 Session；节点缺失时返回 nil。
	内部算法：普通攻击全程开启对应节点内的效果；激光先蓄力、再发射、最后收束。
	不负责：动画选择、伤害、距离判定、目标选择或创建新的特效实例。
]]

local MonsterAttackVFXController = {}

local ATOMIC_EFFECT_NAME = "VFX_ATM1"
local ATOMIC_ENDPOINT_NAME = "ATM2"
local ATOMIC_FIRE_START = 0.28
local ATOMIC_FIRE_END = 0.78

export type Session = {
	Update: (progress: number, targetPosition: Vector3?) -> (),
	Hold: (targetPosition: Vector3?) -> (),
	GetSourcePosition: () -> Vector3?,
	Stop: () -> (),
}

local function isEffect(instance: Instance): boolean
	return instance:IsA("ParticleEmitter")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
end

local function collectEffects(root: Instance): { Instance }
	local effects = {}
	if isEffect(root) then
		table.insert(effects, root)
	end
	for _, descendant in root:GetDescendants() do
		if isEffect(descendant) then
			table.insert(effects, descendant)
		end
	end
	return effects
end

local function setEnabled(effect: Instance, enabled: boolean)
	if effect:IsA("ParticleEmitter")
		or effect:IsA("Beam")
		or effect:IsA("Trail") then
		effect.Enabled = enabled
	end
end

local function disable(effects: { Instance })
	for _, effect in effects do
		setEnabled(effect, false)
	end
end

local function findBeamSourceAttachment(root: Instance): Attachment?
	local function getSource(instance: Instance): Attachment?
		if instance:IsA("Beam") then
			return instance.Attachment0
		end
		return nil
	end

	local rootSource = getSource(root)
	if rootSource then
		return rootSource
	end
	for _, descendant in root:GetDescendants() do
		local source = getSource(descendant)
		if source then
			return source
		end
	end
	return nil
end

-- 输入：尚未进入 Workspace 的运行时克隆。
-- 输出：同一个 Model。
-- 内部算法：只关闭 VFX_ 节点内部的发射器、光束和拖尾，不触碰模型其他常驻效果。
function MonsterAttackVFXController.DisableAll(model: Model): Model
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	for _, descendant in model:GetDescendants() do
		if string.sub(descendant.Name, 1, 4) == "VFX_" then
			disable(collectEffects(descendant))
		end
	end
	return model
end

-- 输入：运行时怪兽模型和激光特效节点名。
-- 输出：该节点内第一个 Beam.Attachment0 的世界坐标；节点或发射点缺失时返回 nil。
-- 副作用：只读取实例，不开启、关闭或移动任何特效。
function MonsterAttackVFXController.GetSourcePosition(
	model: Model,
	effectName: string
): Vector3?
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	assert(type(effectName) == "string" and effectName ~= "", "effectName 必须是非空 string")

	local root = model:FindFirstChild(effectName, true)
	if not root then
		return nil
	end
	local sourceAttachment = findBeamSourceAttachment(root)
	if not sourceAttachment or not sourceAttachment.Parent then
		return nil
	end
	return sourceAttachment.WorldPosition
end

-- 输入：运行时怪兽和本次攻击对应的 VFX 节点名。
-- 输出：节点存在且包含可控效果时返回 Session，否则返回 nil；攻击动画可继续正常播放。
function MonsterAttackVFXController.Start(model: Model, effectName: string?): Session?
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	assert(effectName == nil or type(effectName) == "string", "effectName 必须是 string 或 nil")
	if effectName == nil or effectName == "" then
		return nil
	end

	local root = model:FindFirstChild(effectName, true)
	if not root then
		return nil
	end
	local effects = collectEffects(root)
	if #effects == 0 then
		return nil
	end
	disable(effects)

	local isAtomic = effectName == ATOMIC_EFFECT_NAME
	local endpoint = if isAtomic then root:FindFirstChild(ATOMIC_ENDPOINT_NAME, true) else nil
	local sourceAttachment = if isAtomic then findBeamSourceAttachment(root) else nil
	local stopped = false

	local function update(progress: number, targetPosition: Vector3?)
		assert(
			type(progress) == "number" and progress >= 0 and progress <= 1,
			"progress 必须在 0 到 1 之间"
		)
		assert(
			targetPosition == nil or typeof(targetPosition) == "Vector3",
			"targetPosition 必须是 Vector3 或 nil"
		)
		if stopped then
			return
		end

		if endpoint and endpoint:IsA("Attachment") and targetPosition then
			endpoint.WorldPosition = targetPosition
		end

		if not isAtomic then
			local enabled = progress < 1
			for _, effect in effects do
				setEnabled(effect, enabled)
			end
			return
		end

		local firing = progress >= ATOMIC_FIRE_START and progress < ATOMIC_FIRE_END
		local charging = progress < ATOMIC_FIRE_END
		for _, effect in effects do
			if effect:IsA("Beam") or effect:IsA("Trail") then
				setEnabled(effect, firing)
			elseif endpoint and effect:IsDescendantOf(endpoint) then
				-- 终点爆点只和光束同时出现，避免蓄力时提前暴露命中位置。
				setEnabled(effect, firing)
			else
				setEnabled(effect, charging)
			end
		end
	end

	-- 输入：持续激光当前终点。
	-- 输出：无；保持全部喷射特效开启，并允许每帧移动激光终点。
	local function hold(targetPosition: Vector3?)
		assert(
			targetPosition == nil or typeof(targetPosition) == "Vector3",
			"targetPosition 必须是 Vector3 或 nil"
		)
		if stopped then
			return
		end
		if endpoint and endpoint:IsA("Attachment") and targetPosition then
			endpoint.WorldPosition = targetPosition
		end
		for _, effect in effects do
			setEnabled(effect, true)
		end
	end

	local function getSourcePosition(): Vector3?
		if not sourceAttachment or not sourceAttachment.Parent then
			return nil
		end
		return sourceAttachment.WorldPosition
	end

	local function stop()
		if stopped then
			return
		end
		stopped = true
		disable(effects)
	end

	return {
		Update = update,
		Hold = hold,
		GetSourcePosition = getSourcePosition,
		Stop = stop,
	}
end

return MonsterAttackVFXController
