local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrentBuildings = require(script.Parent.Parent.Building.CurrentBuildings)
local LocalBatchBuilder = require(script.Parent.Parent.Building.LocalBatchBuilder)
local LocalModelPropertyApplier = require(script.Parent.Parent.Building.LocalModelPropertyApplier)
local InstancePath = require(ReplicatedStorage.Shared.InstancePath)
local MonsterAttackTestConfig = require(ReplicatedStorage.Shared.Test.MonsterAttackTestConfig)
local TestHouseCatalog = require(ReplicatedStorage.Shared.Test.MonsterAttackTestHouseCatalog)

local LocalMonsterAttackTestHouses = {}

export type BuildResult = {
	BuiltCount: number,
	Models: { Model },
}

local builtResult: BuildResult? = nil

local function getHousesRoot(): Folder
	local runtime = InstancePath.Get(MonsterAttackTestConfig.Paths.Runtime)
	local houses = runtime:FindFirstChild("Houses")
	if not houses then
		houses = Instance.new("Folder")
		houses.Name = "Houses"
		houses.Parent = runtime
	end
	assert(houses:IsA("Folder"), "测试 Runtime/Houses 必须是 Folder")
	return houses
end

-- 输入：无；房屋模板、放置点和 Runtime 路径由测试配置显式提供。
-- 输出：本地创建的测试房屋数量和模型数组；重复调用返回同一结果。
-- 副作用：
--   在当前客户端并行创建所有测试房屋，放入 Runtime/Houses，
--   并登记 CurrentBuildings，供服务器摧毁通知按 HouseId 播放效果。
function LocalMonsterAttackTestHouses.Build(): BuildResult
	if builtResult then
		return builtResult
	end

	local definitions = TestHouseCatalog.GetAll()
	local items = table.create(#definitions)
	for index, definition in definitions do
		items[index] = {
			Template = definition.Template,
			TargetCFrame = definition.PlacementCFrame,
		}
	end

	local housesRoot = getHousesRoot()
	local models = LocalBatchBuilder.Build(items)
	for index, model in models do
		local definition = definitions[index]
		model.Name = definition.HouseId
		model:SetAttribute("HouseId", definition.HouseId)
		LocalModelPropertyApplier.Apply(model, {
			Anchored = true,
			CanCollide = false,
			CanTouch = false,
			CanQuery = true,
		})
		model.Parent = housesRoot
		CurrentBuildings.Set(definition.Point, definition.HouseId, model)
	end

	builtResult = {
		BuiltCount = #models,
		Models = models,
	}
	return builtResult
end

return LocalMonsterAttackTestHouses
