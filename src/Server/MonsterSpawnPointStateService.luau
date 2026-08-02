--[[
	职责：保存每名玩家每个怪兽出生点的建造状态。

	输入：player、SpawnPointId；写入时额外接收 Level 和 MonsterKey。
	输出：Built、Level、MonsterKey 的快照。
	内部算法：状态写入 ServerStorage 的 MonsterSpawnPoints 分区；新出生点默认为未建造。

	不负责：Zone 解锁、容量、模板解析、模型创建或升级费用。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateService = require(script.Parent.PlayerStateService)
local MonsterSpawnPointCatalog = require(ReplicatedStorage.Shared.Monster.MonsterSpawnPointCatalog)

local MonsterSpawnPointStateService = {}

export type Snapshot = {
	SpawnPointId: string,
	Built: boolean,
	Level: number,
	MonsterKey: string?,
}

local SECTION_NAME = "MonsterSpawnPoints"
local INITIALIZED_ATTRIBUTE = "SpawnPointInitialized"
local started = false

local function getState(player: Player, spawnPointId: string): Folder
	assert(MonsterSpawnPointCatalog.Get(spawnPointId), "未知 SpawnPointId：" .. tostring(spawnPointId))
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
	for _, definition in MonsterSpawnPointCatalog.GetAll() do
		getState(player, definition.SpawnPointId)
	end
end

function MonsterSpawnPointStateService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(initialize)
	for _, player in Players:GetPlayers() do
		initialize(player)
	end
end

function MonsterSpawnPointStateService.Get(player: Player, spawnPointId: string): Snapshot
	return snapshot(getState(player, spawnPointId))
end

-- 输入：持久化适配器已筛选的出生点资产事实。
-- 输出：规范化后的 Built/Level/MonsterKey；不触碰怪兽会话血量和行为状态。
function MonsterSpawnPointStateService.Restore(
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
		MonsterSpawnPointCatalog.GetMonsterKey(spawnPointId, level) == monsterKey,
		"出生点等级与 MonsterKey 不匹配"
	)
	state:SetAttribute("Built", true)
	state:SetAttribute("Level", level)
	state:SetAttribute("MonsterKey", monsterKey)
	return snapshot(state)
end

function MonsterSpawnPointStateService.List(player: Player): { Snapshot }
	initialize(player)
	local result = {}
	for _, definition in MonsterSpawnPointCatalog.GetAll() do
		table.insert(result, snapshot(getState(player, definition.SpawnPointId)))
	end
	return result
end

-- 仅写入已经由上层协调器验证过的建造结果。
function MonsterSpawnPointStateService.MarkBuilt(
	player: Player,
	spawnPointId: string,
	level: number,
	monsterKey: string
): Snapshot
	assert(type(level) == "number" and level >= 1 and level % 1 == 0, "level 必须是正整数")
	assert(type(monsterKey) == "string" and monsterKey ~= "", "monsterKey 必须是非空字符串")
	local state = getState(player, spawnPointId)
	state:SetAttribute("Built", true)
	state:SetAttribute("Level", level)
	state:SetAttribute("MonsterKey", monsterKey)
	return snapshot(state)
end

return MonsterSpawnPointStateService
