local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildJobs = require(ReplicatedStorage.Shared.Building.BuildJobs)
local BuildJobLoader = require(script.Parent.BuildJobLoader)
local CurrentBuildings = require(script.Parent.CurrentBuildings)
local LocalBatchBuilder = require(script.Parent.LocalBatchBuilder)
local LocalBatchDemolisher = require(script.Parent.LocalBatchDemolisher)

local LocalBuildingController = {}

export type BuildingView = {
	HouseId: string,
	Model: Model,
}

local function getJob(jobName: string)
	local job = BuildJobs[jobName]
	assert(job, string.format("找不到建造 Job：%s", jobName))
	return job
end

local function buildItems(items): { BuildingView }
	local models = LocalBatchBuilder.Build(items)
	local buildings = table.create(#models)

	for index, model in ipairs(models) do
		model:SetAttribute("HouseId", items[index].HouseId)
		CurrentBuildings.Set(items[index].Point, items[index].HouseId, model)
		buildings[index] = {
			HouseId = items[index].HouseId,
			Model = model,
		}
	end

	return buildings
end

function LocalBuildingController.Build(jobName: string): { BuildingView }
	local items = BuildJobLoader.Load(getJob(jobName))
	return buildItems(items)
end

function LocalBuildingController.Upgrade(jobName: string): { BuildingView }
	local items = BuildJobLoader.Load(getJob(jobName))
	local oldModels = {}

	for _, item in ipairs(items) do
		local oldModel = CurrentBuildings.TakeByPoint(item.Point)
		if oldModel then
			table.insert(oldModels, oldModel)
		end
	end

	LocalBatchDemolisher.Demolish(oldModels)
	return buildItems(items)
end

return LocalBuildingController
