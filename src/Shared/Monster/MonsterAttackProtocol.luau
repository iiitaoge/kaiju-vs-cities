--[[
	职责：保存正式怪兽攻击网络边界的稳定 Remote 名称。
	不负责：目标查询、命令执行、参数校验、相机或 UI。
]]

return table.freeze({
	TargetQueryRemoteName = "MonsterAttackTargets",
	CommandRemoteName = "MonsterAttackCommand",
})
