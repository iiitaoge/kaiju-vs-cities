local StableModelSpawner = {}

function StableModelSpawner.Spawn(template: Model, targetCFrame: CFrame): Model
	local runtimeModel = template:Clone()
	local primaryPart = assert(runtimeModel.PrimaryPart, "模型必须设置 PrimaryPart")

	for _, descendant in runtimeModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end

	primaryPart.Anchored = true
	runtimeModel:PivotTo(targetCFrame)
	runtimeModel.Parent = workspace

	return runtimeModel
end

return StableModelSpawner
