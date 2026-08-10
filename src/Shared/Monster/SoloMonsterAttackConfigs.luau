--[[
	职责：保存固定单人演示场景的显示、攻击区域和重建配置。
	输入/输出：调用方读取不可变配置。
	不负责：定位场景、读取 Workspace、验证玩家数量、移动怪兽或执行攻击。
]]

return table.freeze({
	ShowcasePlotName = "SoloShowcasePlot",
	AttackableRegionIds = table.freeze({ "R1", "R2" }),
	DisplayName = "Solo Showcase",
	InitialHouseLevel = 1,
	ShowcaseHouseMaxHealth = 1,
	RebuildDelaySeconds = 10,
	RewardAmount = 0,
	CameraFallbackRegionId = "R1",
})
