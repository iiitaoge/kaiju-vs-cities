--[[
	职责：定义客户端界面模式与显示通道之间的纯策略。
	输入：当前模式和界面通道。
	输出：该通道在当前模式下是否允许显示。
	内部算法：普通模式显示常规界面；攻击选择/跟随只显示攻击界面和新手教程。
	不负责：保存业务显隐状态、修改 Instance、管理攻击会话或 Roblox CoreGui。
]]

local UIModeVisibilityRules = {}

UIModeVisibilityRules.Modes = table.freeze({
	Normal = "Normal",
	AttackSelection = "AttackSelection",
	AttackFollow = "AttackFollow",
})

UIModeVisibilityRules.Channels = table.freeze({
	Gameplay = "Gameplay",
	Attack = "Attack",
	Tutorial = "Tutorial",
})

local validModes = table.freeze({
	[UIModeVisibilityRules.Modes.Normal] = true,
	[UIModeVisibilityRules.Modes.AttackSelection] = true,
	[UIModeVisibilityRules.Modes.AttackFollow] = true,
})

local validChannels = table.freeze({
	[UIModeVisibilityRules.Channels.Gameplay] = true,
	[UIModeVisibilityRules.Channels.Attack] = true,
	[UIModeVisibilityRules.Channels.Tutorial] = true,
})

function UIModeVisibilityRules.IsMode(value): boolean
	return type(value) == "string" and validModes[value] == true
end

function UIModeVisibilityRules.IsChannel(value): boolean
	return type(value) == "string" and validChannels[value] == true
end

function UIModeVisibilityRules.Allows(mode: string, channel: string): boolean
	assert(UIModeVisibilityRules.IsMode(mode), "mode 无效")
	assert(UIModeVisibilityRules.IsChannel(channel), "channel 无效")

	if channel == UIModeVisibilityRules.Channels.Tutorial then
		return true
	end
	if mode == UIModeVisibilityRules.Modes.Normal then
		return channel == UIModeVisibilityRules.Channels.Gameplay
	end
	return channel == UIModeVisibilityRules.Channels.Attack
end

return table.freeze(UIModeVisibilityRules)
