--[[
	职责：
	- 为每名在线玩家维护一棵服务器权威的运行时状态树。
	- 状态树存放在未被 Argon 映射的 ServerStorage 中，模块重新加载时仍然存在。
	- 玩家离开时删除对应状态；本模块不提供跨服务器存档。

	输入：
	- Start：无。
	- GetPlayerState / GetSection：player。
	- GetEntity：player、"Zones"、"Houses" 或 "Monsters"、entityId。

	输出：
	- GetPlayerState：玩家状态 Folder。
	- GetSection：Economy / Zones / Houses / Monsters Folder。
	- GetEntity：Zone 或业务实体的状态 Folder。

	内部结构：
	- ServerStorage/RuntimePlayerStates/<UserId>
		- PlayerReference (ObjectValue)
		- Economy (Folder)
		- Zones (Folder)
			- <ZoneId> (Folder + Attributes)
		- Houses (Folder)
			- <HouseId> (Folder + Attributes)
		- Monsters (Folder + Capacity Attribute)
			- <SpawnPointId> (Folder + Attributes)

	不负责：
	- 不解释业务字段，不计算金钱、区域或房屋规则。
	- 不做 DataStore 读写。
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local PlayerStateService = {}

export type SectionName = "Economy" | "Zones" | "Houses" | "Monsters"

-- 权威数据属于下方 Instance 树，而不属于当前 ModuleScript 的执行缓存。
local ROOT_NAME = "RuntimePlayerStates"
local PLAYER_REFERENCE_NAME = "PlayerReference"
local VALID_SECTIONS = {
	Economy = true,
	Zones = true,
	Houses = true,
	Monsters = true,
}

local started = false

local function assertPlayer(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
end

local function getRoot(): Folder
	local existing = ServerStorage:FindFirstChild(ROOT_NAME)
	if existing then
		assert(existing:IsA("Folder"), ROOT_NAME .. " 必须是 Folder")
		return existing
	end

	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root.Parent = ServerStorage
	return root
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), existing:GetFullName() .. " 必须是 Folder")
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function playerStateName(player: Player): string
	return tostring(player.UserId)
end

local function ensurePlayerState(player: Player): Folder
	assertPlayer(player)

	local root = getRoot()
	local stateName = playerStateName(player)
	local existing = root:FindFirstChild(stateName)
	if existing then
		assert(existing:IsA("Folder"), existing:GetFullName() .. " 必须是 Folder")

		local reference = existing:FindFirstChild(PLAYER_REFERENCE_NAME)
		if reference and reference:IsA("ObjectValue") and reference.Value == player then
			for sectionName in pairs(VALID_SECTIONS) do
				ensureFolder(existing, sectionName)
			end
			return existing
		end

		-- 同一服务器中同一 UserId 重新加入时，不能继承上一条 Player 实例的会话状态。
		existing:Destroy()
	end

	local state = Instance.new("Folder")
	state.Name = stateName
	state:SetAttribute("UserId", player.UserId)
	state:SetAttribute("PlayerName", player.Name)

	local reference = Instance.new("ObjectValue")
	reference.Name = PLAYER_REFERENCE_NAME
	reference.Value = player
	reference.Parent = state

	for sectionName in pairs(VALID_SECTIONS) do
		ensureFolder(state, sectionName)
	end

	state.Parent = root
	return state
end

local function removePlayerState(player: Player)
	local root = ServerStorage:FindFirstChild(ROOT_NAME)
	if not root or not root:IsA("Folder") then
		return
	end

	local state = root:FindFirstChild(playerStateName(player))
	if not state or not state:IsA("Folder") then
		return
	end

	local reference = state:FindFirstChild(PLAYER_REFERENCE_NAME)
	if reference and reference:IsA("ObjectValue") and reference.Value == player then
		state:Destroy()
	end
end

function PlayerStateService.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(ensurePlayerState)
	Players.PlayerRemoving:Connect(removePlayerState)

	for _, player in Players:GetPlayers() do
		ensurePlayerState(player)
	end
end

function PlayerStateService.GetPlayerState(player: Player): Folder
	return ensurePlayerState(player)
end

function PlayerStateService.GetSection(player: Player, sectionName: SectionName): Folder
	assert(VALID_SECTIONS[sectionName] == true, "未知玩家状态分区: " .. tostring(sectionName))
	return ensureFolder(ensurePlayerState(player), sectionName)
end

function PlayerStateService.GetEntity(
	player: Player,
	sectionName: "Zones" | "Houses" | "Monsters",
	entityId: string
): Folder
	assert(
		sectionName == "Zones" or sectionName == "Houses" or sectionName == "Monsters",
		"实体只允许放在 Zones、Houses 或 Monsters"
	)
	assert(type(entityId) == "string" and entityId ~= "", "entityId 必须是非空字符串")
	return ensureFolder(PlayerStateService.GetSection(player, sectionName), entityId)
end

return PlayerStateService
