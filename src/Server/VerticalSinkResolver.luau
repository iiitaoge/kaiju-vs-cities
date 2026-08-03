--[[
	职责：计算 BasePart/Model 沉入目标后的世界 Pivot。
	输入：待移动对象和目标 BasePart。
	输出：对象最高点与目标最高点对齐的 CFrame，或稳定失败原因。
	内部算法：使用旋转包围盒在世界 Y 轴上的投影计算最高点，只改变 Y。
	不负责：播放动画、锚定、复位、跟随对象或业务顺序。
]]

local VerticalSinkResolver = {}

export type SinkObject = BasePart | Model

local function getParts(object: SinkObject): { BasePart }
	if object:IsA("BasePart") then
		return { object }
	end
	local parts = {}
	for _, descendant in object:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function getHighestY(part: BasePart): number
	local cframe = part.CFrame
	local size = part.Size
	local verticalHalfExtent = (
		math.abs(cframe.RightVector.Y) * size.X
		+ math.abs(cframe.UpVector.Y) * size.Y
		+ math.abs(cframe.LookVector.Y) * size.Z
	) / 2
	return cframe.Position.Y + verticalHalfExtent
end

local function getPivot(object: SinkObject): CFrame
	return if object:IsA("BasePart") then object.CFrame else object:GetPivot()
end

function VerticalSinkResolver.Resolve(object, target): (CFrame?, string?)
	if typeof(object) ~= "Instance"
		or (not object:IsA("BasePart") and not object:IsA("Model")) then
		return nil, "InvalidObject"
	end
	if typeof(target) ~= "Instance" or not target:IsA("BasePart") then
		return nil, "InvalidTarget"
	end
	if object == target or target:IsDescendantOf(object) then
		return nil, "TargetInsideObject"
	end

	local parts = getParts(object)
	if #parts == 0 then
		return nil, "ObjectHasNoBasePart"
	end
	local objectHighestY = -math.huge
	for _, part in parts do
		objectHighestY = math.max(objectHighestY, getHighestY(part))
	end
	local verticalOffset = getHighestY(target) - objectHighestY
	if verticalOffset > 0 then
		return nil, "TargetAboveObject"
	end
	return getPivot(object) + Vector3.new(0, verticalOffset, 0), nil
end

return VerticalSinkResolver
