local BuildingPlacement = {}

function BuildingPlacement.GetTargetPivot(template: Model, targetCFrame: CFrame): CFrame
	assert(template:IsA("Model"), "template 必须是 Model")
	assert(typeof(targetCFrame) == "CFrame", "targetCFrame 必须是 CFrame")

	local templatePivot = template:GetPivot()
	local templateOrigin = CFrame.new(templatePivot.Position)
	return targetCFrame * templateOrigin:ToObjectSpace(templatePivot)
end

function BuildingPlacement.GetTargetBounds(
	template: Model,
	targetCFrame: CFrame
): (CFrame, Vector3)
	local templatePivot = template:GetPivot()
	local boundingCFrame, boundingSize = template:GetBoundingBox()
	local targetPivot = BuildingPlacement.GetTargetPivot(template, targetCFrame)
	local relativeBoundingCFrame = templatePivot:ToObjectSpace(boundingCFrame)

	return targetPivot * relativeBoundingCFrame, boundingSize
end

return BuildingPlacement
