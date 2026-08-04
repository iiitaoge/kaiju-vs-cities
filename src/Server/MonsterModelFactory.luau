local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildPresentationVisibility = require(
	ReplicatedStorage.Shared.Building.BuildPresentationVisibility
)

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

-- 输入：现有服务器权威怪兽 Model 和完整身份快照。
-- 输出：同一个 Model Instance 更新后的名称与身份 Attributes。
-- 内部算法：不 Clone、不销毁、不触碰部件，只覆盖可复制的权威身份。
function MonsterModelFactory.UpdateIdentity(model: Model, identity: Identity): Model
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")
	assert(type(identity) == "table", "identity 必须是 table")
	model.Name = string.format(
		"%s_%d_%s",
		identity.MonsterKey,
		identity.OwnerUserId,
		identity.SpawnPointId
	)
	applyIdentity(model, identity)
	return model
end

-- 输入：模板、生成位置、运行时父级、完整身份快照，以及可选的建造表现预隐藏标记。
-- 输出：已经放入父级的服务器怪兽模型。
-- 内部算法：克隆模板、解除部件锚定、锚定 PrimaryPart、写入身份；可选预隐藏后再放置。
function MonsterModelFactory.Create(
	template: Model,
	spawnCFrame: CFrame,
	parent: Instance,
	identity: Identity,
	hideForPresentation: boolean?
): Model
	assert(template:IsA("Model"), "template 必须是 Model")
	assert(typeof(spawnCFrame) == "CFrame", "spawnCFrame 必须是 CFrame")
	assert(typeof(parent) == "Instance", "parent 必须是 Instance")
	assert(type(identity) == "table", "identity 必须是 table")
	assert(
		hideForPresentation == nil or type(hideForPresentation) == "boolean",
		"hideForPresentation 必须是 boolean 或 nil"
	)

	local model = template:Clone()
	local primaryPart = assert(model.PrimaryPart, "怪兽模板必须设置 PrimaryPart")
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end
	primaryPart.Anchored = true
	MonsterModelFactory.UpdateIdentity(model, identity)
	model:PivotTo(spawnCFrame)
	if hideForPresentation == true then
		BuildPresentationVisibility.Hide(model)
	end
	model.Parent = parent
	return model
end

-- 输入：旧模型、新模型创建参数，以及可选的建造表现预隐藏标记。
-- 输出：新模型。
-- 内部算法：先完整创建新模型，成功后才销毁旧模型，避免升级失败时丢失实体。
function MonsterModelFactory.Replace(
	previous: Model?,
	template: Model,
	spawnCFrame: CFrame,
	parent: Instance,
	identity: Identity,
	hideForPresentation: boolean?
): Model
	local replacement = MonsterModelFactory.Create(
		template,
		spawnCFrame,
		parent,
		identity,
		hideForPresentation
	)
	if previous and previous.Parent then
		previous:Destroy()
	end
	return replacement
end

return MonsterModelFactory
