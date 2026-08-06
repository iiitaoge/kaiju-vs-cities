local MonsterAttackVFXController = require(
	script.Parent.Parent.MonsterAttackVFXController
)

local MonsterAttackVFXControllerSpec = {}

local function expect(condition: boolean, message: string)
	assert(condition, "MonsterAttackVFXControllerSpec: " .. message)
end

local function makeFixture()
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.CFrame = CFrame.new(10, 5, -4)
	part.Parent = model
	model.PrimaryPart = part

	local normalRoot = Instance.new("Attachment")
	normalRoot.Name = "VFX_tail1"
	normalRoot.Parent = part
	local normalParticle = Instance.new("ParticleEmitter")
	normalParticle.Enabled = true
	normalParticle.Parent = normalRoot

	local atomicRoot = Instance.new("Attachment")
	atomicRoot.Name = "VFX_ATM1"
	atomicRoot.Parent = part
	local source = Instance.new("Attachment")
	source.Name = "ATM1"
	source.Parent = atomicRoot
	local endpoint = Instance.new("Attachment")
	endpoint.Name = "ATM2"
	endpoint.Parent = atomicRoot
	local atomicParticle = Instance.new("ParticleEmitter")
	atomicParticle.Enabled = true
	atomicParticle.Parent = source
	local endpointParticle = Instance.new("ParticleEmitter")
	endpointParticle.Enabled = true
	endpointParticle.Parent = endpoint
	local beam = Instance.new("Beam")
	beam.Attachment0 = source
	beam.Attachment1 = endpoint
	beam.Enabled = true
	beam.Parent = source

	local ambient = Instance.new("ParticleEmitter")
	ambient.Name = "Ambient"
	ambient.Enabled = true
	ambient.Parent = part

	return model, normalParticle, atomicParticle, endpointParticle, beam, endpoint, ambient
end

-- 输入：只存在于测试内的模型与 VFX 节点。
-- 输出：默认关闭、普通攻击全程、激光三阶段和世界终点均满足契约时返回 true。
function MonsterAttackVFXControllerSpec.Run(): boolean
	local model, normalParticle, atomicParticle, endpointParticle, beam, endpoint, ambient = makeFixture()
	local succeeded, message = xpcall(function()
		MonsterAttackVFXController.DisableAll(model)
		expect(not normalParticle.Enabled, "普通攻击特效未默认关闭")
		expect(
			not atomicParticle.Enabled and not endpointParticle.Enabled and not beam.Enabled,
			"激光特效未默认关闭"
		)
		expect(ambient.Enabled, "误关闭了 VFX_ 节点外的常驻特效")

		local normal = assert(MonsterAttackVFXController.Start(model, "VFX_tail1"))
		normal.Update(0, nil)
		expect(normalParticle.Enabled, "普通攻击开始时未开启特效")
		normal.Update(0.99, nil)
		expect(normalParticle.Enabled, "普通攻击结束前过早关闭特效")
		normal.Stop()
		expect(not normalParticle.Enabled, "普通攻击停止后特效仍开启")

		local atomic = assert(MonsterAttackVFXController.Start(model, "VFX_ATM1"))
		local targetPosition = Vector3.new(31, 7, 12)
		atomic.Update(0.1, targetPosition)
		expect(
			atomicParticle.Enabled and not endpointParticle.Enabled and not beam.Enabled,
			"激光蓄力阶段错误"
		)
		expect((endpoint.WorldPosition - targetPosition).Magnitude < 1e-4, "激光终点错误")
		atomic.Update(0.5, targetPosition)
		expect(
			atomicParticle.Enabled and endpointParticle.Enabled and beam.Enabled,
			"激光发射阶段错误"
		)
		atomic.Update(0.9, targetPosition)
		expect(
			not atomicParticle.Enabled and not endpointParticle.Enabled and not beam.Enabled,
			"激光收束阶段错误"
		)
		local sweepTarget = Vector3.new(-20, 9, 44)
		atomic.Hold(sweepTarget)
		expect(
			atomicParticle.Enabled and endpointParticle.Enabled and beam.Enabled,
			"持续激光状态未保持全部特效"
		)
		expect((endpoint.WorldPosition - sweepTarget).Magnitude < 1e-4, "持续激光终点未更新")
		atomic.Stop()
		expect(
			not atomicParticle.Enabled and not endpointParticle.Enabled and not beam.Enabled,
			"持续激光停止后特效仍开启"
		)

		expect(MonsterAttackVFXController.Start(model, "Missing") == nil, "缺失节点应无操作")
	end, debug.traceback)
	model:Destroy()
	assert(succeeded, message)
	return true
end

return MonsterAttackVFXControllerSpec
