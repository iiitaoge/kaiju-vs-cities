local PlayerStateService = require(script.Parent.PlayerStateService)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MonsterCapacityConfig = require(ReplicatedStorage.Shared.Monster.MonsterCapacityConfig)

local MonsterStateService = {}

export type Snapshot = {
	SpawnPointId: string,
	MonsterKey: string,
	State: string,
	Health: number,
	MaxHealth: number,
	SpawnCFrame: CFrame,
	RespawnAt: number?,
}

local function getSection(player: Player): Folder
	local section = PlayerStateService.GetSection(player, "Monsters")
	if section:GetAttribute("Capacity") == nil then
		section:SetAttribute("Capacity", MonsterCapacityConfig.InitialCapacity)
	end
	return section
end

local function snapshot(state: Folder): Snapshot
	return {
		SpawnPointId = state.Name,
		MonsterKey = state:GetAttribute("MonsterKey"),
		State = state:GetAttribute("State"),
		Health = state:GetAttribute("Health"),
		MaxHealth = state:GetAttribute("MaxHealth"),
		SpawnCFrame = state:GetAttribute("SpawnCFrame"),
		RespawnAt = state:GetAttribute("RespawnAt"),
	}
end

local function findState(player: Player, spawnPointId: string): Folder?
	local instance = getSection(player):FindFirstChild(spawnPointId)
	if instance and instance:IsA("Folder") and instance:GetAttribute("Initialized") == true then
		return instance
	end
	return nil
end

function MonsterStateService.GetCapacity(player: Player): number
	return getSection(player):GetAttribute("Capacity") or 0
end

function MonsterStateService.SetCapacity(player: Player, capacity: number): number
	assert(
		type(capacity) == "number"
			and capacity == capacity
			and capacity < math.huge
			and capacity >= 0
			and capacity % 1 == 0,
		"capacity 必须是有限非负整数"
	)
	getSection(player):SetAttribute("Capacity", capacity)
	return capacity
end

-- 载档前清除只属于旧会话的怪兽血量、位置和行为状态；保留 Capacity Attribute。
function MonsterStateService.ClearSession(player: Player): number
	local removedCount = 0
	for _, child in getSection(player):GetChildren() do
		if child:IsA("Folder") then
			child:Destroy()
			removedCount += 1
		end
	end
	return removedCount
end

function MonsterStateService.Get(player: Player, spawnPointId: string): Snapshot?
	local state = findState(player, spawnPointId)
	return if state then snapshot(state) else nil
end

function MonsterStateService.List(player: Player): { Snapshot }
	local result = {}
	for _, child in getSection(player):GetChildren() do
		if child:IsA("Folder") and child:GetAttribute("Initialized") == true then
			table.insert(result, snapshot(child))
		end
	end
	table.sort(result, function(a, b)
		return a.SpawnPointId < b.SpawnPointId
	end)
	return result
end

function MonsterStateService.Create(
	player: Player,
	spawnPointId: string,
	monsterKey: string,
	spawnCFrame: CFrame,
	maxHealth: number
): (Snapshot?, string?)
	if findState(player, spawnPointId) then
		return nil, "SpawnPointAlreadyBound"
	end

	local state = PlayerStateService.GetEntity(player, "Monsters", spawnPointId)
	state:SetAttribute("MonsterKey", monsterKey)
	state:SetAttribute("State", "IdleAtSpawn")
	state:SetAttribute("Health", maxHealth)
	state:SetAttribute("MaxHealth", maxHealth)
	state:SetAttribute("SpawnCFrame", spawnCFrame)
	state:SetAttribute("RespawnAt", nil)
	state:SetAttribute("Initialized", true)
	return snapshot(state), nil
end

function MonsterStateService.SetState(player: Player, spawnPointId: string, value: string): Snapshot?
	local state = findState(player, spawnPointId)
	if not state then
		return nil
	end
	state:SetAttribute("State", value)
	return snapshot(state)
end

function MonsterStateService.SetHealth(player: Player, spawnPointId: string, value: number): Snapshot?
	local state = findState(player, spawnPointId)
	if not state then
		return nil
	end
	state:SetAttribute("Health", value)
	return snapshot(state)
end

function MonsterStateService.SetMonster(
	player: Player,
	spawnPointId: string,
	monsterKey: string,
	maxHealth: number
): Snapshot?
	local state = findState(player, spawnPointId)
	if not state then
		return nil
	end
	state:SetAttribute("MonsterKey", monsterKey)
	state:SetAttribute("MaxHealth", maxHealth)
	state:SetAttribute("Health", maxHealth)
	return snapshot(state)
end

function MonsterStateService.SetRespawnAt(
	player: Player,
	spawnPointId: string,
	value: number?
): Snapshot?
	local state = findState(player, spawnPointId)
	if not state then
		return nil
	end
	state:SetAttribute("RespawnAt", value)
	return snapshot(state)
end

function MonsterStateService.Remove(player: Player, spawnPointId: string): boolean
	local state = findState(player, spawnPointId)
	if not state then
		return false
	end
	state:Destroy()
	return true
end

return MonsterStateService
