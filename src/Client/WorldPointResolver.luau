local WorldPointResolver = {}

local MAX_RAY_DISTANCE = 10_000

function WorldPointResolver.Resolve(screenPosition: Vector2): Vector3?
	assert(typeof(screenPosition) == "Vector2", "screenPosition must be a Vector2")

	local camera = workspace.CurrentCamera
	if camera == nil then
		return nil
	end

	local screenRay = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local result = workspace:Raycast(screenRay.Origin, screenRay.Direction * MAX_RAY_DISTANCE)

	if result == nil then
		return nil
	end

	return result.Position
end

return WorldPointResolver
