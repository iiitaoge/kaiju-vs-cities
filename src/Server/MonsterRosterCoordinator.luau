local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterModelFactory = require(script.Parent.MonsterModelFactory)
local MonsterRuntimeRegistry = require(script.Parent.MonsterRuntimeRegistry)
local MonsterStateService = require(script.Parent.MonsterStateService)
local SpawnPointMonsterBinding = require(script.Parent.SpawnPointMonsterBinding)
local MonsterCapacityRules = require(ReplicatedStorage.Shared.Monster.MonsterCapacityRules)
local MonsterSpawnPointCatalog = require(ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog)
local MonsterStateRules = require(ReplicatedStorage.Shared.Monster.MonsterStateRules)

local MonsterRosterCoordinator = {}

export type MonsterRecord = {
	SpawnPointId: string,
	MonsterKey: string,
	State: string,
	Health: number,
	MaxHealth: number,
	SpawnCFrame: CFrame,
	RespawnAt: number?,
	Model: Model?,
}

export type OperationResult = {
	Succeeded: boolean,
	Reason: string?,
	Record: MonsterRecord?,
}

local started = false

local function resolveRuntimeModel(player: Player, spawnPointId: string): Model?
	local indexed = MonsterRuntimeRegistry.Get(player, spawnPointId)
	if indexed then
		return indexed
	end
	local parent = MonsterRuntimeRegistry.GetParent(player, spawnPointId)
	if not parent then
		return nil
	end
	for _, child in parent:GetChildren() do
		if child:IsA("Model")
			and child:GetAttribute("MonsterSpawnPointId") == spawnPointId
			and child:GetAttribute("MonsterOwnerUserId") == player.UserId then
			MonsterRuntimeRegistry.Set(player, spawnPointId, child)
			return child
		end
	end
	return nil
end

local function recordWithModel(player: Player, snapshot): MonsterRecord
	return {
		SpawnPointId = snapshot.SpawnPointId,
		MonsterKey = snapshot.MonsterKey,
		State = snapshot.State,
		Health = snapshot.Health,
		MaxHealth = snapshot.MaxHealth,
		SpawnCFrame = snapshot.SpawnCFrame,
		RespawnAt = snapshot.RespawnAt,
		Model = resolveRuntimeModel(player, snapshot.SpawnPointId),
	}
end

function MonsterRosterCoordinator.Start()
	if started then
		return
	end
	started = true
	Players.PlayerRemoving:Connect(function(player)
		for _, model in MonsterRuntimeRegistry.Clear(player) do
			if model.Parent then
				model:Destroy()
			end
		end
	end)
end

local function operation(succeeded: boolean, reason: string?, record: MonsterRecord?): OperationResult
	return {
		Succeeded = succeeded,
		Reason = reason,
		Record = record,
	}
end

local function validPositiveNumber(value): boolean
	return type(value) == "number"
		and value == value
		and value < math.huge
		and value > 0
end

function MonsterRosterCoordinator.GetCapacity(player: Player): number
	return MonsterStateService.GetCapacity(player)
end

function MonsterRosterCoordinator.GetCount(player: Player): number
	local count = 0
	for _, record in MonsterStateService.List(player) do
		if MonsterSpawnPointCatalog.Get(record.SpawnPointId) then
			count += 1
		end
	end
	return count
end

-- 输入：玩家和升级逻辑已经算出的绝对容量。
-- 输出：是否成功写入，以及当前数量和容量。
-- 内部算法：调用容量规则验证，不推断升级价格或等级。
function MonsterRosterCoordinator.SetCapacity(player: Player, newCapacity: number)
	local count = MonsterRosterCoordinator.GetCount(player)
	local check = MonsterCapacityRules.CheckSet(count, newCapacity)
	if not check.Allowed then
		return {
			Succeeded = false,
			Reason = check.Reason,
			Count = count,
			Capacity = MonsterStateService.GetCapacity(player),
		}
	end

	MonsterStateService.SetCapacity(player, newCapacity)
	return {
		Succeeded = true,
		Reason = nil,
		Count = count,
		Capacity = newCapacity,
	}
end

function MonsterRosterCoordinator.Get(player: Player, spawnPointId: string): MonsterRecord?
	local snapshot = MonsterStateService.Get(player, spawnPointId)
	return if snapshot then recordWithModel(player, snapshot) else nil
end

function MonsterRosterCoordinator.List(player: Player): { MonsterRecord }
	local result = {}
	for _, snapshot in MonsterStateService.List(player) do
		table.insert(result, recordWithModel(player, snapshot))
	end
	return result
end

local function createForSpawnPoint(
	player: Player,
	spawnPointId: string,
	monsterKey: string,
	template: Model,
	modelScale: number,
	spawnPoint: BasePart,
	maxHealth: number,
	runtimeParent: Instance,
	enforceCapacity: boolean,
	hideForPresentation: boolean
): OperationResult
	assert(player:IsA("Player"), "player 必须是 Player")
	if type(spawnPointId) ~= "string" or spawnPointId == "" then
		return operation(false, "InvalidSpawnPointId", nil)
	end
	if type(monsterKey) ~= "string" or monsterKey == "" then
		return operation(false, "InvalidMonsterKey", nil)
	end
	if not template:IsA("Model") then
		return operation(false, "InvalidTemplate", nil)
	end
	if not validPositiveNumber(modelScale) then
		return operation(false, "InvalidModelScale", nil)
	end
	if typeof(spawnPoint) ~= "Instance" or not spawnPoint:IsA("BasePart") then
		return operation(false, "InvalidSpawnPoint", nil)
	end
	if not validPositiveNumber(maxHealth) then
		return operation(false, "InvalidMaxHealth", nil)
	end
	if typeof(runtimeParent) ~= "Instance" or not runtimeParent:IsDescendantOf(workspace) then
		return operation(false, "InvalidRuntimeParent", nil)
	end
	if MonsterStateService.Get(player, spawnPointId) then
		return operation(false, "SpawnPointAlreadyBound", nil)
	end

	if enforceCapacity then
		local count = MonsterRosterCoordinator.GetCount(player)
		local capacityCheck = MonsterCapacityRules.CheckAdd(
			count,
			MonsterStateService.GetCapacity(player)
		)
		if not capacityCheck.Allowed then
			return operation(false, capacityCheck.Reason, nil)
		end
	end
	local binding = SpawnPointMonsterBinding.Bind(spawnPoint, spawnPointId, monsterKey)
	if not binding.Succeeded then
		return operation(false, binding.Reason, nil)
	end

	local state, stateReason = MonsterStateService.Create(
		player,
		spawnPointId,
		monsterKey,
		spawnPoint.CFrame,
		maxHealth
	)
	if not state then
		if binding.Created then
			SpawnPointMonsterBinding.Unbind(spawnPoint, spawnPointId)
		end
		return operation(false, stateReason or "StateCreateFailed", nil)
	end

	local created, modelOrError = pcall(
		MonsterModelFactory.Create,
		template,
		spawnPoint.CFrame,
		runtimeParent,
		{
			OwnerUserId = player.UserId,
			SpawnPointId = spawnPointId,
			MonsterKey = monsterKey,
			State = state.State,
			Health = state.Health,
			MaxHealth = state.MaxHealth,
		},
		hideForPresentation,
		modelScale
	)
	if not created then
		MonsterStateService.Remove(player, spawnPointId)
		if binding.Created then
			SpawnPointMonsterBinding.Unbind(spawnPoint, spawnPointId)
		end
		warn("创建出生点怪兽失败：", modelOrError)
		return operation(false, "ModelCreateFailed", nil)
	end

	MonsterRuntimeRegistry.SetParent(player, spawnPointId, runtimeParent)
	MonsterRuntimeRegistry.Set(player, spawnPointId, modelOrError)
	return operation(true, nil, recordWithModel(player, state))
end

-- 输入：玩家、唯一出生点、模板身份、模板、绝对 Scale、出生位置、最大生命、运行时父级和可选预隐藏标记。
-- 输出：新增后的怪兽记录或明确失败原因。
-- 内部算法：验证一出生点一怪兽和容量，先建状态，再按要求创建可见或预隐藏模型；失败时回滚状态。
function MonsterRosterCoordinator.CreateForSpawnPoint(
	player: Player,
	spawnPointId: string,
	monsterKey: string,
	template: Model,
	modelScale: number,
	spawnPoint: BasePart,
	maxHealth: number,
	runtimeParent: Instance,
	hideForPresentation: boolean?
): OperationResult
	assert(
		hideForPresentation == nil or type(hideForPresentation) == "boolean",
		"hideForPresentation 必须是 boolean 或 nil"
	)
	return createForSpawnPoint(
		player,
		spawnPointId,
		monsterKey,
		template,
		modelScale,
		spawnPoint,
		maxHealth,
		runtimeParent,
		true,
		hideForPresentation == true
	)
end

-- 仅供服务器加载已保存的已建造出生点；恢复已有资产时不重新套用新增容量限制。
function MonsterRosterCoordinator.RestoreForSpawnPoint(
	player: Player,
	spawnPointId: string,
	monsterKey: string,
	template: Model,
	modelScale: number,
	spawnPoint: BasePart,
	maxHealth: number,
	runtimeParent: Instance
): OperationResult
	return createForSpawnPoint(
		player,
		spawnPointId,
		monsterKey,
		template,
		modelScale,
		spawnPoint,
		maxHealth,
		runtimeParent,
		false,
		false
	)
end

-- 输入：玩家、出生点、目标怪兽模板、绝对 Scale，以及可选的建造表现预隐藏标记。
-- 输出：替换后的怪兽记录。
-- 内部算法：只允许 IdleAtSpawn；先成功创建可见或预隐藏的新模型，再更新状态并替换运行时索引。
function MonsterRosterCoordinator.ReplaceForSpawnPoint(
	player: Player,
	spawnPointId: string,
	newMonsterKey: string,
	template: Model,
	modelScale: number,
	spawnPoint: BasePart,
	maxHealth: number,
	hideForPresentation: boolean?
): OperationResult
	assert(
		hideForPresentation == nil or type(hideForPresentation) == "boolean",
		"hideForPresentation 必须是 boolean 或 nil"
	)
	local current = MonsterStateService.Get(player, spawnPointId)
	if not current then
		return operation(false, "UnknownSpawnPoint", nil)
	end
	local permission = MonsterStateRules.CheckUpgrade(current.State)
	if not permission.Allowed then
		return operation(false, permission.Reason, recordWithModel(player, current))
	end
	if type(newMonsterKey) ~= "string" or newMonsterKey == "" then
		return operation(false, "InvalidMonsterKey", recordWithModel(player, current))
	end
	if not template:IsA("Model") then
		return operation(false, "InvalidTemplate", recordWithModel(player, current))
	end
	if not validPositiveNumber(modelScale) then
		return operation(false, "InvalidModelScale", recordWithModel(player, current))
	end
	if typeof(spawnPoint) ~= "Instance" or not spawnPoint:IsA("BasePart") then
		return operation(false, "InvalidSpawnPoint", recordWithModel(player, current))
	end
	local binding = SpawnPointMonsterBinding.Get(spawnPoint)
	if binding.SpawnPointId ~= spawnPointId or binding.MonsterKey ~= current.MonsterKey then
		return operation(false, "SpawnPointBindingMismatch", recordWithModel(player, current))
	end
	if not validPositiveNumber(maxHealth) then
		return operation(false, "InvalidMaxHealth", recordWithModel(player, current))
	end

	local previous = MonsterRuntimeRegistry.Get(player, spawnPointId)
	local runtimeParent = MonsterRuntimeRegistry.GetParent(player, spawnPointId)
	if not runtimeParent then
		return operation(false, "RuntimeParentUnavailable", recordWithModel(player, current))
	end
	local replaced, modelOrError = pcall(
		MonsterModelFactory.Replace,
		previous,
		template,
		current.SpawnCFrame,
		runtimeParent,
		{
			OwnerUserId = player.UserId,
			SpawnPointId = spawnPointId,
			MonsterKey = newMonsterKey,
			State = current.State,
			Health = maxHealth,
			MaxHealth = maxHealth,
		},
		hideForPresentation,
		modelScale
	)
	if not replaced then
		warn("替换出生点怪兽失败：", modelOrError)
		return operation(false, "ModelReplaceFailed", recordWithModel(player, current))
	end

	local updated = assert(
		MonsterStateService.SetMonster(player, spawnPointId, newMonsterKey, maxHealth),
		"替换模型后怪兽状态意外丢失"
	)
	assert(
		SpawnPointMonsterBinding.SetMonsterKey(spawnPoint, spawnPointId, newMonsterKey),
		"替换模型后出生点绑定意外失效"
	)
	MonsterRuntimeRegistry.Set(player, spawnPointId, modelOrError)
	return operation(true, nil, recordWithModel(player, updated))
end

-- 输入：玩家、出生点和同一形态升级后的怪兽身份、绝对 Scale 与最大生命。
-- 输出：保留原 Model Instance、满血更新后的记录。
-- 内部算法：验证空闲状态、出生点绑定和运行时模型，再同步更新状态、绑定和 Model 身份。
-- 不负责：判断模板是否变化、价格、等级映射或播放表现。
function MonsterRosterCoordinator.UpgradeInPlace(
	player: Player,
	spawnPointId: string,
	newMonsterKey: string,
	modelScale: number,
	spawnPoint: BasePart,
	maxHealth: number
): OperationResult
	local current = MonsterStateService.Get(player, spawnPointId)
	if not current then
		return operation(false, "UnknownSpawnPoint", nil)
	end
	local permission = MonsterStateRules.CheckUpgrade(current.State)
	if not permission.Allowed then
		return operation(false, permission.Reason, recordWithModel(player, current))
	end
	if type(newMonsterKey) ~= "string" or newMonsterKey == "" then
		return operation(false, "InvalidMonsterKey", recordWithModel(player, current))
	end
	if not validPositiveNumber(modelScale) then
		return operation(false, "InvalidModelScale", recordWithModel(player, current))
	end
	if typeof(spawnPoint) ~= "Instance" or not spawnPoint:IsA("BasePart") then
		return operation(false, "InvalidSpawnPoint", recordWithModel(player, current))
	end
	if not validPositiveNumber(maxHealth) then
		return operation(false, "InvalidMaxHealth", recordWithModel(player, current))
	end
	local binding = SpawnPointMonsterBinding.Get(spawnPoint)
	if binding.SpawnPointId ~= spawnPointId or binding.MonsterKey ~= current.MonsterKey then
		return operation(false, "SpawnPointBindingMismatch", recordWithModel(player, current))
	end
	local model = resolveRuntimeModel(player, spawnPointId)
	if not model or not model.Parent then
		return operation(false, "RuntimeModelUnavailable", recordWithModel(player, current))
	end

	local updated = assert(
		MonsterStateService.SetMonster(player, spawnPointId, newMonsterKey, maxHealth),
		"原地升级时怪兽状态意外丢失"
	)
	assert(
		SpawnPointMonsterBinding.SetMonsterKey(spawnPoint, spawnPointId, newMonsterKey),
		"原地升级时出生点绑定意外失效"
	)
	MonsterModelFactory.UpdateIdentity(model, {
		OwnerUserId = player.UserId,
		SpawnPointId = spawnPointId,
		MonsterKey = newMonsterKey,
		State = updated.State,
		Health = updated.Health,
		MaxHealth = updated.MaxHealth,
	})
	MonsterModelFactory.ApplyScale(model, modelScale)
	return operation(true, nil, recordWithModel(player, updated))
end

function MonsterRosterCoordinator.Transition(
	player: Player,
	spawnPointId: string,
	toState: string
): OperationResult
	local current = MonsterStateService.Get(player, spawnPointId)
	if not current then
		return operation(false, "UnknownSpawnPoint", nil)
	end
	local check = MonsterStateRules.CheckTransition(current.State, toState)
	if not check.Allowed then
		return operation(false, check.Reason, recordWithModel(player, current))
	end

	local updated = assert(MonsterStateService.SetState(player, spawnPointId, toState))
	local model = MonsterRuntimeRegistry.Get(player, spawnPointId)
	if model then
		model:SetAttribute("MonsterState", toState)
	end
	return operation(true, nil, recordWithModel(player, updated))
end

function MonsterRosterCoordinator.SetHealth(
	player: Player,
	spawnPointId: string,
	health: number
): OperationResult
	local current = MonsterStateService.Get(player, spawnPointId)
	if not current then
		return operation(false, "UnknownSpawnPoint", nil)
	end
	if type(health) ~= "number"
		or health ~= health
		or health < 0
		or health > current.MaxHealth then
		return operation(false, "InvalidHealth", recordWithModel(player, current))
	end

	local updated = assert(MonsterStateService.SetHealth(player, spawnPointId, health))
	local model = MonsterRuntimeRegistry.Get(player, spawnPointId)
	if model then
		model:SetAttribute("MonsterHealth", health)
	end
	return operation(true, nil, recordWithModel(player, updated))
end

function MonsterRosterCoordinator.DestroyRuntimeModel(player: Player, spawnPointId: string): boolean
	local model = MonsterRuntimeRegistry.Remove(player, spawnPointId)
	if model and model.Parent then
		model:Destroy()
		return true
	end
	return false
end

-- 输入：玩家、出生点身份和该出生点 Instance。
-- 输出：是否删除名册记录；仅允许空闲怪兽被移除。
-- 内部算法：先验证状态与绑定，再删除模型、运行时父级、怪兽状态和出生点绑定。
function MonsterRosterCoordinator.RemoveForSpawnPoint(
	player: Player,
	spawnPointId: string,
	spawnPoint: BasePart
): OperationResult
	local current = MonsterStateService.Get(player, spawnPointId)
	if not current then
		return operation(false, "UnknownSpawnPoint", nil)
	end
	local permission = MonsterStateRules.CheckUpgrade(current.State)
	if not permission.Allowed then
		return operation(false, permission.Reason, recordWithModel(player, current))
	end
	local binding = SpawnPointMonsterBinding.Get(spawnPoint)
	if binding.SpawnPointId ~= spawnPointId or binding.MonsterKey ~= current.MonsterKey then
		return operation(false, "SpawnPointBindingMismatch", recordWithModel(player, current))
	end

	MonsterRosterCoordinator.DestroyRuntimeModel(player, spawnPointId)
	MonsterRuntimeRegistry.RemoveParent(player, spawnPointId)
	MonsterStateService.Remove(player, spawnPointId)
	SpawnPointMonsterBinding.Unbind(spawnPoint, spawnPointId)
	return operation(true, nil, nil)
end

-- 输入：玩家，以及是否同时清除会话怪兽状态。
-- 输出：销毁的运行时模型数量。
-- 内部算法：始终清空模型索引；显式重载时清除 Monsters，离服时由 PlayerStateService 删除整棵状态。
function MonsterRosterCoordinator.UnloadRuntime(
	player: Player,
	clearMonsterState: boolean?
): number
	local removed = MonsterRuntimeRegistry.Clear(player)
	local removedCount = 0
	for _, model in removed do
		if model.Parent then
			model:Destroy()
		end
		removedCount += 1
	end
	if clearMonsterState == true then
		for _, record in MonsterStateService.List(player) do
			MonsterStateService.Remove(player, record.SpawnPointId)
		end
	end
	return removedCount
end

-- 输入：玩家、单个出生点和是否清除该点会话状态。
-- 输出：是否销毁了运行时模型；不触碰同一 Runtime 目录内的其他怪兽。
-- 内部算法：清理模型/父级索引，并按需删除会话记录；出生点 Attribute 由拥有者解绑。
function MonsterRosterCoordinator.UnloadForSpawnPoint(
	player: Player,
	spawnPointId: string,
	clearMonsterState: boolean?
): boolean
	local destroyed = MonsterRosterCoordinator.DestroyRuntimeModel(player, spawnPointId)
	MonsterRuntimeRegistry.RemoveParent(player, spawnPointId)
	if clearMonsterState == true then
		MonsterStateService.Remove(player, spawnPointId)
	end
	return destroyed
end

function MonsterRosterCoordinator.SetRespawnAt(
	player: Player,
	spawnPointId: string,
	respawnAt: number?
): OperationResult
	local updated = MonsterStateService.SetRespawnAt(player, spawnPointId, respawnAt)
	if not updated then
		return operation(false, "UnknownSpawnPoint", nil)
	end
	return operation(true, nil, recordWithModel(player, updated))
end

-- 输入：处于 Recovering 的出生点、当前 MonsterKey 对应模板和绝对 Scale。
-- 输出：重新生成且回到 IdleAtSpawn 的怪兽。
-- 内部算法：使用保存的出生位置和最大生命重建模型，不改变出生点身份。
function MonsterRosterCoordinator.Respawn(
	player: Player,
	spawnPointId: string,
	template: Model,
	modelScale: number
): OperationResult
	local current = MonsterStateService.Get(player, spawnPointId)
	if not current then
		return operation(false, "UnknownSpawnPoint", nil)
	end
	if current.State ~= "Recovering" then
		return operation(false, "MonsterNotRecovering", recordWithModel(player, current))
	end
	if not template:IsA("Model") then
		return operation(false, "InvalidTemplate", recordWithModel(player, current))
	end
	if not validPositiveNumber(modelScale) then
		return operation(false, "InvalidModelScale", recordWithModel(player, current))
	end
	local runtimeParent = MonsterRuntimeRegistry.GetParent(player, spawnPointId)
	if not runtimeParent then
		return operation(false, "RuntimeParentUnavailable", recordWithModel(player, current))
	end

	local created, modelOrError = pcall(
		MonsterModelFactory.Create,
		template,
		current.SpawnCFrame,
		runtimeParent,
		{
			OwnerUserId = player.UserId,
			SpawnPointId = spawnPointId,
			MonsterKey = current.MonsterKey,
			State = "IdleAtSpawn",
			Health = current.MaxHealth,
			MaxHealth = current.MaxHealth,
		},
		nil,
		modelScale
	)
	if not created then
		warn("恢复怪兽模型失败：", modelOrError)
		return operation(false, "ModelCreateFailed", recordWithModel(player, current))
	end

	MonsterRuntimeRegistry.Set(player, spawnPointId, modelOrError)
	MonsterStateService.SetHealth(player, spawnPointId, current.MaxHealth)
	MonsterStateService.SetRespawnAt(player, spawnPointId, nil)
	local transitioned = MonsterRosterCoordinator.Transition(player, spawnPointId, "IdleAtSpawn")
	if not transitioned.Succeeded then
		MonsterRuntimeRegistry.Remove(player, spawnPointId)
		modelOrError:Destroy()
		return transitioned
	end
	return transitioned
end

return MonsterRosterCoordinator
