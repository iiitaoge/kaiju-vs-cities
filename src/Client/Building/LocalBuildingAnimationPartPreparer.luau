--[[
	职责：为本地建筑升降动画准备并排序全部 BasePart 及其表面纹理。
	输入：建筑 Model 和 LowToHigh / HighToLow 排序方向。
	输出：按世界 Y 与稳定完整路径排序的动画项，每项包含 BasePart 及其 Decal/Texture。
	内部算法：遍历全部后代，统一零件物理属性，把表面纹理归属到最近 BasePart，再稳定排序。
	不负责：Clone、Tween、透明度、目标位置、等待或销毁。
]]

local LocalBuildingAnimationPartPreparer = {}

export type Order = "LowToHigh" | "HighToLow"
export type SurfaceVisual = Decal | Texture
export type Item = {
	Part: BasePart,
	SurfaceVisuals: { SurfaceVisual },
}

function LocalBuildingAnimationPartPreparer.Prepare(
	model: Model,
	order: Order
): { Item }
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(order == "LowToHigh" or order == "HighToLow", "order 无效")

	local items = {}
	local itemByPart: { [BasePart]: Item } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			local item = {
				Part = descendant,
				SurfaceVisuals = {},
			}
			itemByPart[descendant] = item
			table.insert(items, item)
		end
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Decal") or descendant:IsA("Texture") then
			local ancestor = descendant.Parent
			while ancestor and ancestor ~= model and not ancestor:IsA("BasePart") do
				ancestor = ancestor.Parent
			end
			if ancestor and ancestor:IsA("BasePart") then
				local item = itemByPart[ancestor]
				if item then
					table.insert(item.SurfaceVisuals, descendant)
				end
			end
		end
	end
	table.sort(items, function(a, b)
		if math.abs(a.Part.Position.Y - b.Part.Position.Y) > 0.01 then
			if order == "LowToHigh" then
				return a.Part.Position.Y < b.Part.Position.Y
			end
			return a.Part.Position.Y > b.Part.Position.Y
		end
		return a.Part:GetFullName() < b.Part:GetFullName()
	end)
	return items
end

return table.freeze(LocalBuildingAnimationPartPreparer)
