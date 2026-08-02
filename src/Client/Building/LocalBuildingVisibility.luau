--[[
	职责：只在当前客户端临时隐藏并恢复一个服务器权威建筑。
	输入：Hide 接收 Model；Restore 接收 Hide 返回的快照。
	输出：每个 BasePart 原本的 LocalTransparencyModifier。
	内部算法：只改 LocalTransparencyModifier，不改服务器 Transparency。
	不负责：不 Clone、不销毁、不播放动画。
]]

local LocalBuildingVisibility = {}

export type Snapshot = { [BasePart]: number }

function LocalBuildingVisibility.Hide(model: Model): Snapshot
	assert(model:IsA("Model"), "model 必须是 Model")
	local snapshot = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			snapshot[descendant] = descendant.LocalTransparencyModifier
			descendant.LocalTransparencyModifier = 1
		end
	end
	return snapshot
end

function LocalBuildingVisibility.Restore(snapshot: Snapshot)
	for part, value in snapshot do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end
end

return LocalBuildingVisibility
