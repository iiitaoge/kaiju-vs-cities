--[[
	职责：把指定玩家 Plot 中的服务器运行时塔转换为 DefenseTowerAccess 快照。
	输入：防守玩家。
	输出：按 TowerId 排序的当前已解锁、身份有效的塔目标。
	内部算法：Plot/Runtime/DefenseTowers 直系实例 → 身份/归属/Zone/Slot/配置校验 → 世界位置。
	不负责：生成塔、保存塔、升级、选敌、冷却、伤害或表现。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerPlotAssignmentService = require(script.Parent.PlayerPlotAssignmentService)
local ZoneStateService = require(script.Parent.ZoneStateService)
local DefenseTowerConfigs = require(ReplicatedStorage.Shared.Monster.DefenseTowerConfigs)
local RuntimeDefenseTowerIdentity = require(
	ReplicatedStorage.Shared.Monster.RuntimeDefenseTowerIdentity
)
local ZoneCatalog = require(ReplicatedStorage.Shared.World.ZoneCatalog)

local PlayerRuntimeDefenseTowerAccess = {}

local function resolvePosition(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

function PlayerRuntimeDefenseTowerAccess.ListAliveTowers(player: Player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "player 必须是 Player")
	local plot = PlayerPlotAssignmentService.GetPlot(player)
	if not plot then
		return {}
	end
	local runtime = plot:FindFirstChild("Runtime")
	local towersRoot = runtime and runtime:FindFirstChild("DefenseTowers")
	if not towersRoot or not towersRoot:IsA("Folder") then
		return {}
	end

	local candidates = {}
	local countsByTowerId = {}
	for _, instance in towersRoot:GetChildren() do
		local identity = RuntimeDefenseTowerIdentity.Read(instance)
		if not identity
			or identity.OwnerUserId ~= player.UserId
			or not ZoneStateService.GetUnlocked(player, identity.ZoneId) then
			continue
		end
		local zone = ZoneCatalog.Get(identity.ZoneId)
		local slot = ZoneCatalog.GetSlot(identity.ZoneId, identity.SlotId)
		if not zone or zone.Kind ~= "Defense"
			or not slot or slot.Kind ~= "DefenseTower" then
			continue
		end
		local config = DefenseTowerConfigs.Get(identity.ConfigId)
		local position = resolvePosition(instance)
		if not config or not position then
			continue
		end
		countsByTowerId[identity.TowerId] = (countsByTowerId[identity.TowerId] or 0) + 1
		table.insert(candidates, {
			Identity = identity,
			Position = position,
			Config = config,
		})
	end

	local towers = {}
	for _, candidate in candidates do
		local identity = candidate.Identity
		if countsByTowerId[identity.TowerId] ~= 1 then
			continue
		end
		local config = candidate.Config
		table.insert(towers, {
			TowerId = identity.TowerId,
			Position = candidate.Position,
			Range = config.Range,
			Damage = config.Damage,
			AttackInterval = config.AttackInterval,
			Active = identity.Active,
		})
	end
	table.sort(towers, function(a, b)
		return a.TowerId < b.TowerId
	end)
	return towers
end

return PlayerRuntimeDefenseTowerAccess
