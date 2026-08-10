--[[
	职责：从已验证模板创建一个服务器权威罐体 Model。
	输入：模板、目标 Pivot、Runtime Folder、完整身份，以及可选的建造表现预隐藏标记。
	输出：已经定位并挂入 Runtime 的罐体 Model。
	内部算法：Clone、写入身份、将全部零件固定为非物理并锚定、PivotTo；可选预隐藏后再 Parent。
	不负责：解析模板/Plot、播放动画、创建怪兽、状态或失败退款。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildPresentationVisibility = require(
	ReplicatedStorage.Shared.Building.BuildPresentationVisibility
)

local MonsterIncubatorFactory = {}

export type Identity = {
	OwnerUserId: number,
	SpawnPointId: string,
	ZoneId: string,
	TemplateId: string,
}

local function assertNonEmpty(value: string, fieldName: string)
	assert(type(value) == "string" and value ~= "", fieldName .. " 必须是非空字符串")
end

function MonsterIncubatorFactory.Create(
	template: Model,
	targetCFrame: CFrame,
	parent: Folder,
	identity: Identity,
	hideForPresentation: boolean?
): Model
	assert(typeof(template) == "Instance" and template:IsA("Model"), "template 必须是 Model")
	assert(typeof(targetCFrame) == "CFrame", "targetCFrame 必须是 CFrame")
	assert(typeof(parent) == "Instance" and parent:IsA("Folder"), "parent 必须是 Folder")
	assert(type(identity) == "table", "identity 必须是 table")
	assert(
		type(identity.OwnerUserId) == "number"
			and identity.OwnerUserId == identity.OwnerUserId
			and identity.OwnerUserId % 1 == 0
			and identity.OwnerUserId ~= 0,
		"OwnerUserId 必须是非零整数"
	)
	assertNonEmpty(identity.SpawnPointId, "SpawnPointId")
	assertNonEmpty(identity.ZoneId, "ZoneId")
	assertNonEmpty(identity.TemplateId, "TemplateId")
	assert(
		hideForPresentation == nil or type(hideForPresentation) == "boolean",
		"hideForPresentation 必须是 boolean 或 nil"
	)

	local model = template:Clone()
	model.Name = identity.SpawnPointId
	model:SetAttribute("IncubatorOwnerUserId", identity.OwnerUserId)
	model:SetAttribute("IncubatorSpawnPointId", identity.SpawnPointId)
	model:SetAttribute("IncubatorZoneId", identity.ZoneId)
	model:SetAttribute("IncubatorTemplateId", identity.TemplateId)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			-- 培养罐只负责视觉和 UI 锚点，不能参与人物/怪兽物理。
			-- 不能只依赖模板属性，否则换形态时新罐体可能把角色夹住。
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	model:PivotTo(targetCFrame)
	if hideForPresentation == true then
		BuildPresentationVisibility.Hide(model)
	end
	model.Parent = parent
	return model
end

return MonsterIncubatorFactory
