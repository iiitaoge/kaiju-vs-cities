local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterModelFactory = require(script.Parent.MonsterModelFactory)
local MonsterRuntimeRegistry = require(script.Parent.MonsterRuntimeRegistry)
local MonsterStateService = require(script.Parent.MonsterStateService)
local SpawnPointMonsterBinding = require(script.Parent.SpawnPointMonsterBinding)
local MonsterCapacityRules = require(ReplicatedStorage.Shared.Monster.MonsterCapacityRules)
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

local RUNTIME_ROOT_NAME = "RuntimeMonsters"
local started = false

local function runtimeRoot(): Folder
	local existing = workspace:FindFirstChild(RUNTIME_ROOT_NAME)
	if existing then
		assert(existing:IsA("Folder"), RUNTIME_ROOT_NAME .. " 必须是 Folder")
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = RUNTIME_ROOT_NAME
	folder.Parent = workspace
	return folder
end

local function playerRuntimeRoot(player: Player): Folder
	local root = runtimeRoot()
	local name = tostring(player.UserId)
	local existing = root:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), existing:GetFullName() .. " 必须是 Folder")
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder:SetAttribute("OwnerUserId", player.UserId)
	folder.Parent = root
	return folder
end

local function resolveRuntimeModel(player: Player, spawnPointId: string): Model?
	local indexed = MonsterRuntimeRegistry.Get(player, spawnPointId)
	if indexed then
		return indexed
	end
	for _, child in playerRuntimeRoot(player):GetChildren() do
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
		local root = workspace:FindFirstChild(RUNTIME_ROOT_NAME)
		local playerRoot = root and root:FindFirstChild(tostring(player.UserId))
		if playerRoot then
			playerRoot:Destroy()
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
	return #MonsterStateService.List(player)
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

-- 输入：玩家、唯一出生点、模板身份、模板、出生位置和最大生命。
-- 输出：新增后的怪兽记录或明确失败原因。
-- 内部算法：验证一出生点一怪兽和容量，先建状态，再创建服务器模型；失败时回滚状态。
function MonsterRosterCoordinator.CreateForSpawnPoint(
	player: Player,
	spawnPointId: string,
	monsterKey: string,
	template: Model,
	spawnPoint: BasePart,
	maxHealth: number
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
	if typeof(spawnPoint) ~= "Instance" or not spawnPoint:IsA("BasePart") then
		return operation(false, "InvalidSpawnPoint", nil)
	end
	if not validPositiveNumber(maxHealth) then
		return operation(false, "InvalidMaxHealth", nil)
	end
	if MonsterStateService.Get(player, spawnPointId) then
		return operation(false, "SpawnPointAlreadyBound", nil)
	end

	local count = MonsterRosterCoordinator.GetCount(player)
	local capacityCheck = MonsterCapacityRules.CheckAdd(
		count,
		MonsterStateService.GetCapacity(player)
	)
	if not capacityCheck.Allowed then
		return operation(false, capacityCheck.Reason, nil)
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
		playerRuntimeRoot(player),
		{
			OwnerUserId = player.UserId,
			SpawnPointId = spawnPointId,
			MonsterKey = monsterKey,
			State = state.State,
			Health = state.Health,
			MaxHealth = state.MaxHealth,
		}
	)
	if not created then
		MonsterStateService.Remove(player, spawnPointId)
		if binding.Created then
			SpawnPointMonsterBinding.Unbind(spawnPoint, spawnPointId)
		end
		warn("创建出生点怪兽失败：", modelOrError)
		return operation(false, "ModelCreateFailed", nil)
	end

	MonsterRuntimeRegistry.Set(player, spawnPointId, modelOrError)
	return operation(true, nil, recordWithModel(player, state))
end

-- 输入：玩家、出生点和目标怪兽模板。
-- 输出：替换后的怪兽记录。
-- 内部算法：只允许 IdleAtSpawn；先成功创建新模型，再更新状态并替换运行时索引。
function MonsterRosterCoordinator.ReplaceForSpawnPoint(
	player: Player,
	spawnPointId: string,
	newMonsterKey: string,
	template: Model,
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
	if not template:IsA("Model") then
		return operation(false, "InvalidTemplate", recordWithModel(player, current))
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
	local replaced, modelOrError = pcall(
		MonsterModelFactory.Replace,
		previous,
		template,
		current.SpawnCFrame,
		playerRuntimeRoot(player),
		{
			OwnerUserId = player.UserId,
			SpawnPointId = spawnPointId,
			MonsterKey = newMonsterKey,
			State = current.State,
			Health = maxHealth,
			MaxHealth = maxHealth,
		}
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

-- 输入：处于 Recovering 的出生点和当前 MonsterKey 对应模板。
-- 输出：重新生成且回到 IdleAtSpawn 的怪兽。
-- 内部算法：使用保存的出生位置和最大生命重建模型，不改变出生点身份。
function MonsterRosterCoordinator.Respawn(
	player: Player,
	spawnPointId: string,
	template: Model
): OperationResult
	local current = MonsterStateService.Get(player, spawnPointId)
	if not current then
		return operation(false, "UnknownSpawnPoint", nil)
	end
	if current.State ~= "Recovering" then
		return operation(false, "MonsterNotRecovering", recordWithModel(player, current))
	end

	local created, modelOrError = pcall(
		MonsterModelFactory.Create,
		template,
		current.SpawnCFrame,
		playerRuntimeRoot(player),
		{
			OwnerUserId = player.UserId,
			SpawnPointId = spawnPointId,
			MonsterKey = current.MonsterKey,
			State = "IdleAtSpawn",
			Health = current.MaxHealth,
			MaxHealth = current.MaxHealth,
		}
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
