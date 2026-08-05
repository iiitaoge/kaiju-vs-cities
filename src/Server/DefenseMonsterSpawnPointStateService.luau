--[[
	职责：保存每名玩家每个收入区域防守怪兽的独立等级资产。
	输入：Player、防守 SpawnPointId；Restore/MarkBuilt 接收等级和 MonsterKey。
	输出：Built、Level、MonsterKey 快照。
	内部算法：使用独立 DefenseMonsterSpawnPoints 分区，不占用进攻怪兽容量或出生点资产。
	不负责：解锁、模型、战斗、复活、价格或 UI。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateService = require(script.Parent.PlayerStateService)
local DefenseMonsterSlotCatalog = require(
	ReplicatedStorage.Shared.Monster.DefenseMonsterSlotCatalog
)

local DefenseMonsterSpawnPointStateService = {}

export type Snapshot = {
	SpawnPointId: string,
	Built: boolean,
	Level: number,
	MonsterKey: string?,
}

local SECTION_NAME = "DefenseMonsterSpawnPoints"
local INITIALIZED_ATTRIBUTE = "DefenseMonsterInitialized"
local started = false

local function getState(player: Player, spawnPointId: string): Folder
	assert(DefenseMonsterSlotCatalog.Get(spawnPointId), "未知防守 SpawnPointId：" .. tostring(spawnPointId))
	local state = PlayerStateService.GetEntity(player, SECTION_NAME, spawnPointId)
	if state:GetAttribute(INITIALIZED_ATTRIBUTE) ~= true then
		state:SetAttribute("Built", false)
		state:SetAttribute("Level", 0)
		state:SetAttribute("MonsterKey", nil)
		state:SetAttribute(INITIALIZED_ATTRIBUTE, true)
	end
	return state
end

local function snapshot(state: Folder): Snapshot
	local monsterKey = state:GetAttribute("MonsterKey")
	return {
		SpawnPointId = state.Name,
		Built = state:GetAttribute("Built") == true,
		Level = state:GetAttribute("Level") or 0,
		MonsterKey = if type(monsterKey) == "string" then monsterKey else nil,
	}
end

local function initialize(player: Player)
	for _, definition in DefenseMonsterSlotCatalog.GetAll() do
		getState(player, definition.SpawnPointId)
	end
end

function DefenseMonsterSpawnPointStateService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(initialize)
	for _, player in Players:GetPlayers() do
		initialize(player)
	end
end

function DefenseMonsterSpawnPointStateService.Get(player: Player, spawnPointId: string): Snapshot
	return snapshot(getState(player, spawnPointId))
end

function DefenseMonsterSpawnPointStateService.Restore(
	player: Player,
	spawnPointId: string,
	built: boolean,
	level: number,
	monsterKey: string?
): Snapshot
	assert(type(built) == "boolean", "built 必须是 boolean")
	local state = getState(player, spawnPointId)
	if not built then
		state:SetAttribute("Built", false)
		state:SetAttribute("Level", 0)
		state:SetAttribute("MonsterKey", nil)
		return snapshot(state)
	end

	assert(type(level) == "number" and level >= 1 and level % 1 == 0, "level 必须是正整数")
	assert(type(monsterKey) == "string" and monsterKey ~= "", "monsterKey 必须是非空字符串")
	assert(
		DefenseMonsterSlotCatalog.GetMonsterKey(spawnPointId, level) == monsterKey,
		"防守怪兽等级与 MonsterKey 不匹配"
	)
	state:SetAttribute("Built", true)
	state:SetAttribute("Level", level)
	state:SetAttribute("MonsterKey", monsterKey)
	return snapshot(state)
end

function DefenseMonsterSpawnPointStateService.MarkBuilt(
	player: Player,
	spawnPointId: string,
	level: number,
	monsterKey: string
): Snapshot
	return DefenseMonsterSpawnPointStateService.Restore(
		player,
		spawnPointId,
		true,
		level,
		monsterKey
	)
end

function DefenseMonsterSpawnPointStateService.List(player: Player): { Snapshot }
	initialize(player)
	local result = {}
	for _, definition in DefenseMonsterSlotCatalog.GetAll() do
		table.insert(result, snapshot(getState(player, definition.SpawnPointId)))
	end
	return result
end

return DefenseMonsterSpawnPointStateService
