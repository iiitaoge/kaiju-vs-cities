--[[
	职责：
	- 保存所有类型 Zone 共用的 Unlocked 和 Level 状态。
	- 以 Shared.World.ZoneCatalog 为身份来源，不解释 Zone 的具体 Kind。

	输入：
	- player、zoneId，以及 Setter 的新值。

	输出：
	- Get：Unlocked、Level 快照。
	- Getter/Setter：对应字段值。

	内部算法：
	- 状态写入 ServerStorage/RuntimePlayerStates/<UserId>/Zones/<ZoneId> Attributes。
	- 新玩家按 ZoneCatalog.InitialUnlocked 和默认 Level 0 初始化。

	不负责：
	- 不执行产钱、怪兽出生或其他 Zone Kind 的业务。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateService = require(script.Parent.PlayerStateService)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local ZoneStateService = {}

local DEFAULT_LEVEL = 0

local function getDefinition(zoneId: string): ZoneCatalog.ZoneDefinition?
	if type(zoneId) ~= "string" or zoneId == "" then
		return nil
	end
	return ZoneCatalog.Get(zoneId)
end

local function getZoneState(player: Player, zoneId: string): Folder
	assert(getDefinition(zoneId), string.format("未知 ZoneId：%s", tostring(zoneId)))
	return PlayerStateService.GetEntity(player, "Zones", zoneId)
end

local function initialize(player: Player)
	for _, definition in ZoneCatalog.GetAll() do
		local state = getZoneState(player, definition.ZoneId)
		if state:GetAttribute("Unlocked") == nil then
			state:SetAttribute("Unlocked", definition.InitialUnlocked)
		end
		if state:GetAttribute("Level") == nil then
			state:SetAttribute("Level", DEFAULT_LEVEL)
		end
	end
end

function ZoneStateService.Start()
	Players.PlayerAdded:Connect(initialize)

	for _, player in Players:GetPlayers() do
		initialize(player)
	end
end

function ZoneStateService.Get(player: Player, zoneId: string)
	return {
		Unlocked = ZoneStateService.GetUnlocked(player, zoneId),
		Level = ZoneStateService.GetLevel(player, zoneId),
	}
end

function ZoneStateService.GetUnlocked(player: Player, zoneId: string): boolean
	local definition = getDefinition(zoneId)
	if not definition then
		return false
	end

	local value = getZoneState(player, zoneId):GetAttribute("Unlocked")
	return if value == nil then definition.InitialUnlocked else value
end

function ZoneStateService.SetUnlocked(player: Player, zoneId: string, value: boolean): boolean
	assert(type(value) == "boolean", "value 必须是 boolean")
	getZoneState(player, zoneId):SetAttribute("Unlocked", value)
	return value
end

function ZoneStateService.GetLevel(player: Player, zoneId: string): number
	if not getDefinition(zoneId) then
		return DEFAULT_LEVEL
	end
	return getZoneState(player, zoneId):GetAttribute("Level") or DEFAULT_LEVEL
end

function ZoneStateService.SetLevel(player: Player, zoneId: string, value: number): number
	assert(
		type(value) == "number"
			and value == value
			and value < math.huge
			and value >= 0
			and value % 1 == 0,
		"value 必须是有限非负整数"
	)
	getZoneState(player, zoneId):SetAttribute("Level", value)
	return value
end

return ZoneStateService
