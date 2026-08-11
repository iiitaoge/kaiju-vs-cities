--[[
	职责：定义怪兽使用钻石一次升至满级的专属价格。
	输入：ProgressionId。
	输出：对应成长线的 MaxUpgradeCost。
	内部算法：纯配置；不读取余额、不执行升级或修改运行时状态。
]]

local configs = {
	Godzilla = {
		MaxUpgradeCost = 2_000,
	},
}

for progressionId, config in pairs(configs) do
	assert(
		type(config.MaxUpgradeCost) == "number"
			and config.MaxUpgradeCost > 0
			and config.MaxUpgradeCost < math.huge
			and config.MaxUpgradeCost % 1 == 0,
		progressionId .. " MaxUpgradeCost 无效"
	)
	table.freeze(config)
end

return table.freeze(configs)
