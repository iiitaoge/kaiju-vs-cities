--[[
	职责：管理并验证 Plot/Runtime/MonsterIncubators 中的服务器权威罐体。
	输入：Plot、SpawnPointId；创建目录或删除时接收明确操作参数。
	输出：Runtime Folder、罐体合同或稳定失败原因。
	内部算法：固定 Runtime 路径、唯一名称、身份、直接子级和锚定状态验证。
	不负责：模板、世界定位、Clone、动画、怪兽状态或购买事务。
]]

local WorkspaceMonsterIncubatorAccess = {}

export type Incubator = {
	Model: Model,
	Base: Model,
	Liquid: BasePart,
	Glass: BasePart,
	Target: BasePart,
}

local ROOT_NAME = "MonsterIncubators"

local function findUniqueChild(parent: Instance, name: string): (Instance?, string?)
	local found = nil
	for _, child in parent:GetChildren() do
		if child.Name == name then
			if found then
				return nil, "Duplicate" .. name
			end
			found = child
		end
	end
	return found, nil
end

local function allPartsAnchored(object: Instance): boolean
	local foundPart = false
	if object:IsA("BasePart") then
		foundPart = true
		if not object.Anchored then
			return false
		end
	end
	for _, descendant in object:GetDescendants() do
		if descendant:IsA("BasePart") then
			foundPart = true
			if not descendant.Anchored then
				return false
			end
		end
	end
	return foundPart
end

local function getRuntime(plot: Model): Folder?
	local runtime = plot:FindFirstChild("Runtime")
	return if runtime and runtime:IsA("Folder") then runtime else nil
end

function WorkspaceMonsterIncubatorAccess.GetOrCreateRoot(
	plot: Model
): (Folder?, string?)
	if typeof(plot) ~= "Instance" or not plot:IsA("Model") then
		return nil, "InvalidPlot"
	end
	local runtime = getRuntime(plot)
	if not runtime then
		return nil, "MissingPlotRuntime"
	end
	local existing = runtime:FindFirstChild(ROOT_NAME)
	if existing then
		if not existing:IsA("Folder") then
			return nil, "InvalidMonsterIncubatorRuntime"
		end
		return existing, nil
	end
	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root.Parent = runtime
	return root, nil
end

function WorkspaceMonsterIncubatorAccess.GetRoot(plot: Model): Folder?
	if typeof(plot) ~= "Instance" or not plot:IsA("Model") then
		return nil
	end
	local runtime = getRuntime(plot)
	local root = runtime and runtime:FindFirstChild(ROOT_NAME)
	return if root and root:IsA("Folder") then root else nil
end

function WorkspaceMonsterIncubatorAccess.Resolve(
	plot: Model,
	spawnPointId: string
): (Incubator?, string?)
	if typeof(plot) ~= "Instance" or not plot:IsA("Model") then
		return nil, "InvalidPlot"
	end
	if type(spawnPointId) ~= "string" or spawnPointId == "" then
		return nil, "InvalidSpawnPointId"
	end
	local root = WorkspaceMonsterIncubatorAccess.GetRoot(plot)
	if not root then
		return nil, "MissingMonsterIncubatorRuntime"
	end
	local model, modelReason = findUniqueChild(root, spawnPointId)
	if modelReason then
		return nil, "DuplicateMonsterIncubator"
	end
	if not model or not model:IsA("Model") then
		return nil, "MissingMonsterIncubator"
	end
	if model:GetAttribute("IncubatorSpawnPointId") ~= spawnPointId then
		return nil, "MonsterIncubatorIdentityMismatch"
	end
	local ownerUserId = plot:GetAttribute("OwnerUserId")
	if type(ownerUserId) == "number"
		and ownerUserId ~= 0
		and model:GetAttribute("IncubatorOwnerUserId") ~= ownerUserId then
		return nil, "MonsterIncubatorOwnerMismatch"
	end

	local base, baseReason = findUniqueChild(model, "Base")
	local liquid, liquidReason = findUniqueChild(model, "Liquid")
	local glass, glassReason = findUniqueChild(model, "Glass")
	local target, targetReason = findUniqueChild(model, "Target")
	local duplicateReason = baseReason or liquidReason or glassReason or targetReason
	if duplicateReason then
		return nil, duplicateReason
	end
	if not base or not base:IsA("Model") then
		return nil, "InvalidIncubatorBase"
	end
	if not liquid or not liquid:IsA("BasePart") then
		return nil, "InvalidIncubatorLiquid"
	end
	if not glass or not glass:IsA("BasePart") then
		return nil, "InvalidIncubatorGlass"
	end
	if not target or not target:IsA("BasePart") then
		return nil, "InvalidIncubatorTarget"
	end
	if not allPartsAnchored(model) then
		return nil, "MonsterIncubatorMustBeAnchored"
	end

	return {
		Model = model,
		Base = base,
		Liquid = liquid,
		Glass = glass,
		Target = target,
	}, nil
end

function WorkspaceMonsterIncubatorAccess.Remove(
	plot: Model,
	spawnPointId: string,
	expectedModel: Model?
): (boolean, string?)
	local root = WorkspaceMonsterIncubatorAccess.GetRoot(plot)
	if not root then
		return false, "MissingMonsterIncubatorRuntime"
	end
	local current, duplicateReason = findUniqueChild(root, spawnPointId)
	if duplicateReason then
		return false, "DuplicateMonsterIncubator"
	end
	if not current or not current:IsA("Model") then
		return false, "MissingMonsterIncubator"
	end
	if expectedModel and current ~= expectedModel then
		return false, "MonsterIncubatorChanged"
	end
	current:Destroy()
	if #root:GetChildren() == 0 then
		root:Destroy()
	end
	return true, nil
end

return WorkspaceMonsterIncubatorAccess
