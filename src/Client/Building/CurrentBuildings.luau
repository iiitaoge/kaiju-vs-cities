local CurrentBuildings = {}

type BuildingRecord = {
	Point: BasePart,
	HouseId: string,
	Model: Model,
}

local recordsByPoint: { [BasePart]: BuildingRecord } = {}
local recordsByHouseId: { [string]: BuildingRecord } = {}

local function removeRecord(record: BuildingRecord): Model
	if recordsByPoint[record.Point] == record then
		recordsByPoint[record.Point] = nil
	end
	if recordsByHouseId[record.HouseId] == record then
		recordsByHouseId[record.HouseId] = nil
	end

	return record.Model
end

function CurrentBuildings.Set(point: BasePart, houseId: string, model: Model)
	assert(point:IsA("BasePart"), "point 必须是 BasePart")
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
	assert(model:IsA("Model"), "model 必须是 Model")

	local pointRecord = recordsByPoint[point]
	local houseRecord = recordsByHouseId[houseId]
	if pointRecord then
		removeRecord(pointRecord)
	end
	if houseRecord and houseRecord ~= pointRecord then
		removeRecord(houseRecord)
	end

	local record = {
		Point = point,
		HouseId = houseId,
		Model = model,
	}
	recordsByPoint[point] = record
	recordsByHouseId[houseId] = record
end

function CurrentBuildings.GetByPoint(point: BasePart): Model?
	local record = recordsByPoint[point]
	return if record then record.Model else nil
end

function CurrentBuildings.GetByHouseId(houseId: string): Model?
	local record = recordsByHouseId[houseId]
	return if record then record.Model else nil
end

function CurrentBuildings.TakeByPoint(point: BasePart): Model?
	local record = recordsByPoint[point]
	return if record then removeRecord(record) else nil
end

function CurrentBuildings.TakeByHouseId(houseId: string): Model?
	local record = recordsByHouseId[houseId]
	return if record then removeRecord(record) else nil
end

return CurrentBuildings
