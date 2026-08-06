--[[
	职责：定义战斗血条模板和服务器镜像 Attribute 的稳定名称。
	输入/输出：无函数；客户端与服务端只读常量。
	不负责：计算血量比例、判断显示状态、创建 UI 或拥有战斗状态。
]]

return table.freeze({
	TemplateFolderName = "UI",
	TemplateName = "blood",
	LocalAttachmentName = "LocalCombatHealthBar",

	MonsterStateAttributeName = "MonsterState",
	MonsterCurrentHealthAttributeName = "MonsterHealth",
	MonsterMaxHealthAttributeName = "MonsterMaxHealth",

	HouseActiveAttackCountAttributeName = "BuildingActiveAttackCount",
})
