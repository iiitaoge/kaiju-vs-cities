--[[
	职责：管理并验证 Plot/Runtime/MonsterIncubators 中的服务器权威罐体。
	输入：Plot、SpawnPointId；创建目录或删除时接收明确操作参数。
	输出：Runtime Folder、含 MonsterHomeAttachment 的罐体合同或稳定失败原因。
	内部算法：固定 Runtime 路径、唯一名称、身份、直接子级和锚定状态验证。
	不负责：模板、世界定位、Clone、动画、怪兽状态或购买事务。
]]

local AnchoredPartRules = require(script.Parent.AnchoredPartRules)
local UniqueNamedChildAccess = require(script.Parent.UniqueNamedChildAccess)

local WorkspaceMonsterIncubatorAccess = {}

export type Incubator = {
	Model: Model,
	Base: Model,
	MonsterHomeAttachment: Attachment,
	Liquid: BasePart | Model,
	Glass: BasePart,
	Target: BasePart,
}

local ROOT_NAME = "MonsterIncubators"

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
	local model, modelDuplicated = UniqueNamedChildAccess.Find(root, spawnPointId)
	if modelDuplicated then
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

	local base, baseDuplicated = UniqueNamedChildAccess.Find(model, "Base")
	if baseDuplicated then
		return nil, "DuplicateBase"
	end
	local liquid, liquidDuplicated = UniqueNamedChildAccess.Find(model, "Liquid")
	if liquidDuplicated then
		return nil, "DuplicateLiquid"
	end
	local glass, glassDuplicated = UniqueNamedChildAccess.Find(model, "Glass")
	if glassDuplicated then
		return nil, "DuplicateGlass"
	end
	local target, targetDuplicated = UniqueNamedChildAccess.Find(model, "Target")
	if targetDuplicated then
		return nil, "DuplicateTarget"
	end
	if not base or not base:IsA("Model") then
		return nil, "InvalidIncubatorBase"
	end
	local monsterHome, monsterHomeDuplicated = UniqueNamedChildAccess.Find(
		base,
		"MonsterHomeAttachment"
	)
	if monsterHomeDuplicated then
		return nil, "DuplicateMonsterHomeAttachment"
	end
	if not monsterHome or not monsterHome:IsA("Attachment") then
		return nil, "InvalidMonsterHomeAttachment"
	end
	if not liquid or (not liquid:IsA("BasePart") and not liquid:IsA("Model")) then
		return nil, "InvalidIncubatorLiquid"
	end
	if not glass or not glass:IsA("BasePart") then
		return nil, "InvalidIncubatorGlass"
	end
	if not target or not target:IsA("BasePart") then
		return nil, "InvalidIncubatorTarget"
	end
	if not AnchoredPartRules.HasOnlyAnchoredParts(model) then
		return nil, "MonsterIncubatorMustBeAnchored"
	end

	return {
		Model = model,
		Base = base,
		MonsterHomeAttachment = monsterHome,
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
	local current, currentDuplicated = UniqueNamedChildAccess.Find(
		root,
		spawnPointId
	)
	if currentDuplicated then
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
