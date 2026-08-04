--[[
	职责：只在当前客户端临时隐藏并恢复一个服务器权威建筑。
	输入：Hide 接收 Model；Restore 接收 Hide 返回的快照。
	输出：每个 BasePart 原本的 LocalTransparencyModifier，以及 Decal/Texture 的 Transparency。
	内部算法：对零件使用本地透明度；对独立表面纹理临时修改 Transparency，并提供完整恢复快照。
	不负责：不 Clone、不销毁、不播放动画。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildPresentationVisibility = require(
	ReplicatedStorage.Shared.Building.BuildPresentationVisibility
)

local LocalBuildingVisibility = {}

export type SurfaceVisual = Decal | Texture
export type Snapshot = {
	Parts: { [BasePart]: number },
	SurfaceVisuals: { [SurfaceVisual]: number },
}

function LocalBuildingVisibility.Hide(model: Model): Snapshot
	assert(model:IsA("Model"), "model 必须是 Model")
	local snapshot: Snapshot = {
		Parts = {},
		SurfaceVisuals = {},
	}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			snapshot.Parts[descendant] = descendant.LocalTransparencyModifier
			descendant.LocalTransparencyModifier = 1
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			snapshot.SurfaceVisuals[descendant] =
				BuildPresentationVisibility.ResolveTransparency(descendant)
			descendant.Transparency = 1
		end
	end
	return snapshot
end

function LocalBuildingVisibility.Restore(snapshot: Snapshot)
	for part, value in snapshot.Parts do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end
	for surfaceVisual, value in snapshot.SurfaceVisuals do
		if surfaceVisual.Parent then
			surfaceVisual.Transparency = value
		end
	end
end

return LocalBuildingVisibility
