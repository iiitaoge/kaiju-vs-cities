local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.UI.UIModeVisibilityRules)

local Spec = {}

function Spec.Run(): boolean
	local modes = Rules.Modes
	local channels = Rules.Channels

	assert(Rules.Allows(modes.Normal, channels.Gameplay), "普通模式应显示常规界面")
	assert(not Rules.Allows(modes.Normal, channels.Attack), "普通模式不应显示攻击界面")
	assert(Rules.Allows(modes.Normal, channels.Combat), "普通模式应显示战斗血条")
	assert(Rules.Allows(modes.Normal, channels.Tutorial), "普通模式应显示教程")

	for _, mode in { modes.AttackSelection, modes.AttackFollow } do
		assert(not Rules.Allows(mode, channels.Gameplay), "攻击独占模式应隐藏常规界面")
		assert(Rules.Allows(mode, channels.Attack), "攻击独占模式应显示攻击界面")
		assert(Rules.Allows(mode, channels.Combat), "攻击独占模式必须显示战斗血条")
		assert(Rules.Allows(mode, channels.Tutorial), "攻击独占模式必须保留教程")
	end
	return true
end

return Spec
