--[[
	职责：
	- 维护服务器内 Player + HouseId 到运行时建筑 Model 的索引。

	输入：
	- Player、稳定 HouseId，以及可选 Model。

	输出：
	- Set 返回被替换的旧 Model。
	- Get / Remove 返回对应 Model。
	- List 返回调用方可修改的新映射。
	- Clear 返回移除索引前仍然有效的 Model 数组。

	不负责：
	- 不创建或销毁 Instance，不读取房屋状态，不操作 Plot。
]]

local PlayerBuildingRuntimeRegistry = {}

local modelsByPlayer: { [Player]: { [string]: Model } } = setmetatable({}, { __mode = "k" })

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function assertHouseId(houseId: string)
	assert(type(houseId) == "string" and houseId ~= "", "houseId 必须是非空字符串")
end

local function playerModels(player: Player): { [string]: Model }
	local models = modelsByPlayer[player]
	if not models then
		models = {}
		modelsByPlayer[player] = models
	end
	return models
end

function PlayerBuildingRuntimeRegistry.Set(
	player: Player,
	houseId: string,
	model: Model
): Model?
	assertPlayer(player)
	assertHouseId(houseId)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "model 必须是 Model")

	local models = playerModels(player)
	local previous = models[houseId]
	models[houseId] = model
	return previous
end

function PlayerBuildingRuntimeRegistry.Get(player: Player, houseId: string): Model?
	assertPlayer(player)
	assertHouseId(houseId)

	local models = modelsByPlayer[player]
	local model = models and models[houseId]
	if model and not model.Parent then
		models[houseId] = nil
		return nil
	end
	return model
end

function PlayerBuildingRuntimeRegistry.Remove(player: Player, houseId: string): Model?
	assertPlayer(player)
	assertHouseId(houseId)

	local models = modelsByPlayer[player]
	if not models then
		return nil
	end
	local model = models[houseId]
	models[houseId] = nil
	if next(models) == nil then
		modelsByPlayer[player] = nil
	end
	return model
end

function PlayerBuildingRuntimeRegistry.List(player: Player): { [string]: Model }
	assertPlayer(player)
	local result = {}
	local models = modelsByPlayer[player]
	if not models then
		return result
	end

	for houseId, model in pairs(models) do
		if model.Parent then
			result[houseId] = model
		else
			models[houseId] = nil
		end
	end
	if next(models) == nil then
		modelsByPlayer[player] = nil
	end
	return result
end

function PlayerBuildingRuntimeRegistry.Clear(player: Player): { Model }
	assertPlayer(player)
	local models = modelsByPlayer[player]
	modelsByPlayer[player] = nil
	local removed = {}
	if not models then
		return removed
	end

	for _, model in pairs(models) do
		if model.Parent then
			table.insert(removed, model)
		end
	end
	return removed
end

return PlayerBuildingRuntimeRegistry
