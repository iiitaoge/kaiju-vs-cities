local MonsterRuntimeRegistry = {}

local modelsByPlayer: { [Player]: { [string]: Model } } = setmetatable({}, { __mode = "k" })

local function getPlayerModels(player: Player): { [string]: Model }
	local models = modelsByPlayer[player]
	if not models then
		models = {}
		modelsByPlayer[player] = models
	end
	return models
end

-- 输入：玩家、稳定出生点 ID 和 Workspace 怪兽模型。
-- 输出：替换前的旧模型；没有时返回 nil。
-- 内部算法：只维护内存索引，不克隆或销毁模型。
function MonsterRuntimeRegistry.Set(player: Player, spawnPointId: string, model: Model): Model?
	assert(player:IsA("Player"), "player 必须是 Player")
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 无效")
	assert(model:IsA("Model"), "model 必须是 Model")
	local models = getPlayerModels(player)
	local previous = models[spawnPointId]
	models[spawnPointId] = model
	return previous
end

function MonsterRuntimeRegistry.Get(player: Player, spawnPointId: string): Model?
	local models = modelsByPlayer[player]
	local model = models and models[spawnPointId]
	if model and model:IsDescendantOf(workspace) then
		return model
	end
	if models then
		models[spawnPointId] = nil
	end
	return nil
end

function MonsterRuntimeRegistry.Remove(player: Player, spawnPointId: string): Model?
	local models = modelsByPlayer[player]
	if not models then
		return nil
	end
	local model = models[spawnPointId]
	models[spawnPointId] = nil
	return model
end

function MonsterRuntimeRegistry.List(player: Player): { [string]: Model }
	local result = {}
	local models = modelsByPlayer[player]
	if not models then
		return result
	end
	for spawnPointId, model in models do
		if model:IsDescendantOf(workspace) then
			result[spawnPointId] = model
		else
			models[spawnPointId] = nil
		end
	end
	return result
end

function MonsterRuntimeRegistry.Clear(player: Player): { Model }
	local removed = {}
	local models = modelsByPlayer[player]
	modelsByPlayer[player] = nil
	if not models then
		return removed
	end
	for _, model in models do
		table.insert(removed, model)
	end
	return removed
end

return MonsterRuntimeRegistry
