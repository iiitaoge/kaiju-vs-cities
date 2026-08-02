local TerritoryPointRules = {}

export type CheckOptions = {
	-- 正值扩大有效范围，负值缩小有效范围。
	HorizontalPadding: number?,
}

export type CheckResult = {
	Allowed: boolean,
	Reason: string?,
	LocalPoint: Vector3?,
}

local function isFiniteNumber(value): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function isFiniteVector3(value): boolean
	return typeof(value) == "Vector3"
		and isFiniteNumber(value.X)
		and isFiniteNumber(value.Y)
		and isFiniteNumber(value.Z)
end

-- 输入：地盘包围盒、世界坐标和可选水平边距。
-- 输出：坐标是否落在地盘的 X/Z 范围内，以及对应局部坐标。
-- 内部算法：把世界坐标转换到地盘局部空间，只验证水平边界。
function TerritoryPointRules.Check(
	territoryCFrame: CFrame,
	territorySize: Vector3,
	worldPoint: Vector3,
	options: CheckOptions?
): CheckResult
	if typeof(territoryCFrame) ~= "CFrame"
		or not isFiniteVector3(territorySize)
		or territorySize.X <= 0
		or territorySize.Z <= 0 then
		return {
			Allowed = false,
			Reason = "InvalidTerritory",
			LocalPoint = nil,
		}
	end
	if not isFiniteVector3(worldPoint) then
		return {
			Allowed = false,
			Reason = "InvalidEntryPoint",
			LocalPoint = nil,
		}
	end

	local padding = if options and options.HorizontalPadding ~= nil
		then options.HorizontalPadding
		else 0
	if not isFiniteNumber(padding) then
		return {
			Allowed = false,
			Reason = "InvalidPadding",
			LocalPoint = nil,
		}
	end

	local halfX = territorySize.X * 0.5 + padding
	local halfZ = territorySize.Z * 0.5 + padding
	if halfX < 0 or halfZ < 0 then
		return {
			Allowed = false,
			Reason = "InvalidTerritory",
			LocalPoint = nil,
		}
	end

	local localPoint = territoryCFrame:PointToObjectSpace(worldPoint)
	local allowed = math.abs(localPoint.X) <= halfX and math.abs(localPoint.Z) <= halfZ
	return {
		Allowed = allowed,
		Reason = if allowed then nil else "EntryPointOutsideTerritory",
		LocalPoint = localPoint,
	}
end

return TerritoryPointRules
