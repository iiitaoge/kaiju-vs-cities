--[[
	职责：保存产钱建筑各 Zone 等级对应的最大生命值。
	输入：GetMaxHealth 接收 RegionId 和正整数等级。
	输出：配置存在时返回最大生命值，否则返回 nil。
	不负责：当前血量、伤害、房屋状态、运行时模型或存档。
]]

local StructureDurabilityConfigs = {}

local maxHealthByRegion = {
	R1 = {
		[1] = 100,
		[2] = 160,
		[3] = 240,
	},
	R2 = {
		[1] = 200,
		[2] = 320,
		[3] = 480,
	},
	R3 = {
		[1] = 400,
		[2] = 640,
		[3] = 960,
	},
	R4 = {
		[1] = 800,
		[2] = 1200,
		[3] = 1800,
		[4] = 2700,
		[5] = 4000,
		[6] = 6000,
		[7] = 9000,
		[8] = 13500,
	},
	R5 = {
		[1] = 1000,
		[2] = 1500,
		[3] = 2250,
		[4] = 3375,
		[5] = 5000,
		[6] = 7500,
	},
}

for _, levels in maxHealthByRegion do
	for level, maxHealth in levels do
		assert(type(level) == "number" and level >= 1 and level % 1 == 0, "建筑耐久等级无效")
		assert(type(maxHealth) == "number" and maxHealth > 0, "建筑最大生命值无效")
	end
	table.freeze(levels)
end
table.freeze(maxHealthByRegion)

function StructureDurabilityConfigs.GetMaxHealth(regionId: string, level: number): number?
	local levels = maxHealthByRegion[regionId]
	return if levels then levels[level] else nil
end

return table.freeze(StructureDurabilityConfigs)
