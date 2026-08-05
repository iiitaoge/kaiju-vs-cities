--[[
	职责：保存单人空地出征的稳定场景名称、显示名和攻击表演时长。
	输入/输出：调用方读取不可变配置。
	不负责：读取 Workspace、验证玩家数量、移动怪兽或播放动画。
]]

return table.freeze({
	BoundsPartName = "SoloAttackBounds",
	DisplayName = "Solo Attack",
	AttackDuration = 3,
})
