local LocalModelPropertyApplier = {}

export type Properties = {
	Anchored: boolean?,
	CanCollide: boolean?,
	CanTouch: boolean?,
	CanQuery: boolean?,
	CastShadow: boolean?,
}

export type PartState = {
	Anchored: boolean,
	CanCollide: boolean,
	CanTouch: boolean,
	CanQuery: boolean,
	CastShadow: boolean,
}

export type Snapshot = { [BasePart]: PartState }

function LocalModelPropertyApplier.Apply(model: Model, properties: Properties): Snapshot
	assert(model:IsA("Model"), "model 必须是 Model")

	local snapshot = {}
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		snapshot[descendant] = {
			Anchored = descendant.Anchored,
			CanCollide = descendant.CanCollide,
			CanTouch = descendant.CanTouch,
			CanQuery = descendant.CanQuery,
			CastShadow = descendant.CastShadow,
		}

		if properties.Anchored ~= nil then
			descendant.Anchored = properties.Anchored
		end
		if properties.CanCollide ~= nil then
			descendant.CanCollide = properties.CanCollide
		end
		if properties.CanTouch ~= nil then
			descendant.CanTouch = properties.CanTouch
		end
		if properties.CanQuery ~= nil then
			descendant.CanQuery = properties.CanQuery
		end
		if properties.CastShadow ~= nil then
			descendant.CastShadow = properties.CastShadow
		end
	end

	return snapshot
end

function LocalModelPropertyApplier.Restore(snapshot: Snapshot)
	for part, state in snapshot do
		if not part.Parent then
			continue
		end

		part.Anchored = state.Anchored
		part.CanCollide = state.CanCollide
		part.CanTouch = state.CanTouch
		part.CanQuery = state.CanQuery
		part.CastShadow = state.CastShadow
	end
end

return LocalModelPropertyApplier
