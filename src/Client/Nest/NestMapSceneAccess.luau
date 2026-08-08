--[[
	职责：查找公共 Nest 及其 CameraMarker。
	输入：NestId。
	输出：Workspace/Nests/<NestId> 的 Model 或其 CameraMarker BasePart。
	内部算法：按 NestCatalog.WorldRootName 查找唯一根节点，再查找直接子级。
	不负责：镜头控制、占用状态、派遣或 UI。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NestCatalog = require(ReplicatedStorage.Shared.Nest.NestCatalog)
local NestMapCameraConfigs = require(
	ReplicatedStorage.Shared.Nest.NestMapCameraConfigs
)

local NestMapSceneAccess = {}

function NestMapSceneAccess.GetNest(nestId: string): (Model?, string?)
	if type(nestId) ~= "string" or nestId == "" then
		return nil, "InvalidNestId"
	end
	local root = workspace:FindFirstChild(NestCatalog.WorldRootName)
	if not root then
		return nil, "NestRootUnavailable"
	end
	local nest = root:FindFirstChild(nestId)
	if not nest then
		return nil, "NestUnavailable"
	end
	if not nest:IsA("Model") then
		return nil, "NestInvalid"
	end
	return nest, nil
end

function NestMapSceneAccess.GetCameraMarker(nestId: string): (BasePart?, string?)
	local nest, nestReason = NestMapSceneAccess.GetNest(nestId)
	if not nest then
		return nil, nestReason
	end
	local marker = nest:FindFirstChild(NestMapCameraConfigs.MarkerName)
	if not marker then
		return nil, "CameraMarkerUnavailable"
	end
	if not marker:IsA("BasePart") then
		return nil, "CameraMarkerMustBeBasePart"
	end
	return marker, nil
end

return table.freeze(NestMapSceneAccess)
