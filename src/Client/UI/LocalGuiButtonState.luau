--[[
	职责：统一本地 GuiButton 的可交互状态。
	输入：GuiButton 和是否允许交互。
	输出：Active、Interactable、Selectable、AutoButtonColor 保持一致；提供统一可交互判断。
	内部算法：业务按钮启用时同时打开四个交互属性；判断时额外确认按钮及其祖先仍处于可见状态。
	不负责：按钮业务、请求、动画、音效或面板显隐。
]]

local LocalGuiButtonState = {}

local function isVisibleInHierarchy(button: GuiButton): boolean
	local current: Instance? = button
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
end

function LocalGuiButtonState.SetEnabled(button: GuiButton, enabled: boolean)
	button.Active = enabled
	button.Interactable = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
end

function LocalGuiButtonState.IsEnabled(button: GuiButton): boolean
	return button.Active
		and button.Interactable
		and isVisibleInHierarchy(button)
end

return table.freeze(LocalGuiButtonState)
