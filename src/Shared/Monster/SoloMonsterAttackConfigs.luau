--[[
	职责：保存单人空 Plot 出征的显示配置和攻击表演时长。
	输入/输出：调用方读取不可变配置。
	不负责：定位展示 Plot、读取 Workspace、验证玩家数量、移动怪兽或播放动画。
]]

return table.freeze({
	BoundsPartName = "AttackViewBounds",
	DisplayName = "Empty Plot",
	AttackDuration = 3,
	CameraFallbackRegionId = "R1",
})
