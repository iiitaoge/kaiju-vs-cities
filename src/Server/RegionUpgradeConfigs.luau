--[[
	职责：
	- 描述 UpgradeRegion 动作在每个目标等级需要执行的配置效果。

	输入：
	- 无。

	输出：
	- 以 RegionId 为键、Level 为次级键的只读配置。

	读取模块：
	- RegionUpgradeService。

	写入模块：
	- 无。运行时模块不得修改本配置。

	字段：
	- PresentationId：
	  升级提交并刷新服务器建筑后，选择 Shared.Building.BuildingPresentationConfigs
	  中的一套纯表现参数。

	说明：
	- 本配置描述 UpgradeRegion 自己的效果。
	- 其他按钮 Action 不会被收入系统推断成 UpgradeRegion。
]]

local MAX_REGION_LEVEL = 30

local function region()
	local levels = {}
	for level = 1, MAX_REGION_LEVEL do
		levels[level] = table.freeze({ PresentationId = "Standard" })
	end
	return table.freeze({ Levels = table.freeze(levels) })
end

return table.freeze({
	R1 = region(),
	R2 = region(),
	R3 = region(),
	R4 = region(),
	R5 = region(),
	R6 = region(),
})
