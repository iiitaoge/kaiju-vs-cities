local MonsterRuntimeRegistry = {}

local modelsByPlayer: { [Player]: { [string]: Model } } = setmetatable({}, { __mode = "k" })
local parentsByPlayer: { [Player]: { [string]: Instance } } = setmetatable({}, { __mode = "k" })

local function getPlayerModels(player: Player): { [string]: Model }
	local models = modelsByPlayer[player]
	if not models then
		models = {}
		modelsByPlayer[player] = models
	end
	return models
end

local function getPlayerParents(player: Player): { [string]: Instance }
	local parents = parentsByPlayer[player]
	if not parents then
		parents = {}
		parentsByPlayer[player] = parents
	end
	return parents
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

-- 模型死亡后仍保留运行时父级，使恢复流程能回到原玩家 Plot。
function MonsterRuntimeRegistry.SetParent(
	player: Player,
	spawnPointId: string,
	parent: Instance
): Instance?
	assert(player:IsA("Player"), "player 必须是 Player")
	assert(type(spawnPointId) == "string" and spawnPointId ~= "", "spawnPointId 无效")
	assert(typeof(parent) == "Instance", "parent 必须是 Instance")
	local parents = getPlayerParents(player)
	local previous = parents[spawnPointId]
	parents[spawnPointId] = parent
	return previous
end

function MonsterRuntimeRegistry.GetParent(player: Player, spawnPointId: string): Instance?
	local parents = parentsByPlayer[player]
	local parent = parents and parents[spawnPointId]
	if parent and parent.Parent then
		return parent
	end
	if parents then
		parents[spawnPointId] = nil
	end
	return nil
end

function MonsterRuntimeRegistry.RemoveParent(player: Player, spawnPointId: string): Instance?
	local parents = parentsByPlayer[player]
	if not parents then
		return nil
	end
	local parent = parents[spawnPointId]
	parents[spawnPointId] = nil
	return parent
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
	parentsByPlayer[player] = nil
	if not models then
		return removed
	end
	for _, model in models do
		table.insert(removed, model)
	end
	return removed
end

return MonsterRuntimeRegistry
