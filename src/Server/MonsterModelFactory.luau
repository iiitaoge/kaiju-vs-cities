local MonsterModelFactory = {}

export type Identity = {
	OwnerUserId: number,
	SpawnPointId: string,
	MonsterKey: string,
	State: string,
	Health: number,
	MaxHealth: number,
}

local function applyIdentity(model: Model, identity: Identity)
	model:SetAttribute("MonsterOwnerUserId", identity.OwnerUserId)
	model:SetAttribute("MonsterSpawnPointId", identity.SpawnPointId)
	model:SetAttribute("MonsterKey", identity.MonsterKey)
	model:SetAttribute("MonsterState", identity.State)
	model:SetAttribute("MonsterHealth", identity.Health)
	model:SetAttribute("MonsterMaxHealth", identity.MaxHealth)
end

-- 输入：模板、生成位置、运行时父级和完整身份快照。
-- 输出：已经放入父级的服务器怪兽模型。
-- 内部算法：克隆模板、解除部件锚定、锚定 PrimaryPart、写入身份并放置。
function MonsterModelFactory.Create(
	template: Model,
	spawnCFrame: CFrame,
	parent: Instance,
	identity: Identity
): Model
	assert(template:IsA("Model"), "template 必须是 Model")
	assert(typeof(spawnCFrame) == "CFrame", "spawnCFrame 必须是 CFrame")
	assert(typeof(parent) == "Instance", "parent 必须是 Instance")
	assert(type(identity) == "table", "identity 必须是 table")

	local model = template:Clone()
	local primaryPart = assert(model.PrimaryPart, "怪兽模板必须设置 PrimaryPart")
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
	primaryPart.Anchored = true
	model.Name = string.format("%s_%d_%s", identity.MonsterKey, identity.OwnerUserId, identity.SpawnPointId)
	applyIdentity(model, identity)
	model:PivotTo(spawnCFrame)
	model.Parent = parent
	return model
end

-- 输入：旧模型和新模型创建参数。
-- 输出：新模型。
-- 内部算法：先完整创建新模型，成功后才销毁旧模型，避免升级失败时丢失实体。
function MonsterModelFactory.Replace(
	previous: Model?,
	template: Model,
	spawnCFrame: CFrame,
	parent: Instance,
	identity: Identity
): Model
	local replacement = MonsterModelFactory.Create(template, spawnCFrame, parent, identity)
	if previous and previous.Parent then
		previous:Destroy()
	end
	return replacement
end

return MonsterModelFactory
