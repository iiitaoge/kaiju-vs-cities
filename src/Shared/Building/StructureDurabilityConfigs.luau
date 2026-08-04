--[[
	职责：保存 R1～R6 产钱建筑的 30 级基础生命曲线。
	输入：GetMaxHealth 接收 RegionId 和正整数等级。
	输出：配置存在时返回最大生命值，否则返回 nil。
	不负责：当前血量、伤害、房屋状态、运行时模型或存档。
]]

local StructureDurabilityConfigs = {}

local MAX_LEVEL = 30
local configs = {
	R1 = { BaseMaxHealth = 200, LevelGrowth = 1.08 },
	R2 = { BaseMaxHealth = 800, LevelGrowth = 1.08 },
	R3 = { BaseMaxHealth = 3_000, LevelGrowth = 1.08 },
	R4 = { BaseMaxHealth = 10_000, LevelGrowth = 1.08 },
	R5 = { BaseMaxHealth = 30_000, LevelGrowth = 1.08 },
	R6 = { BaseMaxHealth = 90_000, LevelGrowth = 1.08 },
}

for regionId, config in configs do
	assert(type(config.BaseMaxHealth) == "number" and config.BaseMaxHealth > 0, regionId .. " 基础生命无效")
	assert(type(config.LevelGrowth) == "number" and config.LevelGrowth > 1, regionId .. " 生命成长无效")
	table.freeze(config)
end
table.freeze(configs)

function StructureDurabilityConfigs.GetMaxHealth(regionId: string, level: number): number?
	local config = configs[regionId]
	if not config
		or type(level) ~= "number"
		or level < 1
		or level > MAX_LEVEL
		or level % 1 ~= 0
	then
		return nil
	end
	return math.floor(config.BaseMaxHealth * config.LevelGrowth ^ (level - 1) + 0.5)
end

return table.freeze(StructureDurabilityConfigs)
