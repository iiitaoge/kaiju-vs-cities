--[[
	职责：解析一名玩家某产钱区域等级的有效建筑最大生命。
	输入：Player、RegionId、Level。
	输出：基础生命、玩家倍率和有效最大生命；失败时返回稳定原因。
	内部算法：读取基础配置和玩家倍率，再调用纯生命规则缩放。
	不负责：创建血量状态、修改模型、伤害或持久化。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RegionStateService = require(script.Parent.RegionStateService)
local StructureDurabilityConfigs = require(
	ReplicatedStorage.Shared.Building.StructureDurabilityConfigs
)
local StructureHealthRules = require(
	ReplicatedStorage.Shared.Building.StructureHealthRules
)

local PlayerStructureDurabilityResolver = {}

function PlayerStructureDurabilityResolver.Resolve(
	player: Player,
	regionId: string,
	level: number
)
	local baseMaxHealth = StructureDurabilityConfigs.GetMaxHealth(regionId, level)
	if not baseMaxHealth then
		return nil, "DurabilityConfigUnavailable"
	end
	local healthMultiplier = RegionStateService.GetHealthMultiplier(player, regionId)
	local maxHealth = StructureHealthRules.ScaleMaxHealth(
		baseMaxHealth,
		healthMultiplier
	)
	if not maxHealth then
		return nil, "InvalidHealthMultiplier"
	end
	return {
		BaseMaxHealth = baseMaxHealth,
		HealthMultiplier = healthMultiplier,
		MaxHealth = maxHealth,
	}, nil
end

return PlayerStructureDurabilityResolver
