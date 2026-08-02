local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local IncomeZoneConfigs = require(ReplicatedStorage.Shared.Building.IncomeZoneConfigs)

local BuildJobLoader = {}

function BuildJobLoader.Load(job)
	local region = assert(
		IncomeZoneConfigs[job.RegionId],
		string.format("产钱 Zone 配置不存在：%s", job.RegionId)
	)
	local items = {}

	for groupName, entries in pairs(region.Groups) do
		for _, entry in ipairs(entries) do
			local modelPath = string.format(
				"%s/%s/%s/level%d",
				region.ModelRoot,
				groupName,
				entry.VariantName,
				job.Level
			)
			local pointPath = string.format("%s/%s/%s", region.PointRoot, groupName, entry.PointName)
			local template = InstancePath.Wait(modelPath)
			local point = InstancePath.Wait(pointPath)

			assert(template:IsA("Model"), string.format("建筑模板不是 Model：%s", modelPath))
			assert(point:IsA("BasePart"), string.format("放置点不是 BasePart：%s", pointPath))

			table.insert(items, {
				HouseId = entry.HouseId,
				RegionId = job.RegionId,
				Level = job.Level,
				Template = template,
				Point = point,
				TargetCFrame = point.CFrame,
			})
		end
	end

	return items
end

return BuildJobLoader
