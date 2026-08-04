--[[
	职责：按固定层级解析 Rebirth-Button 的物理 Pull 和 BillboardGui 控件。
	输入：Rebirth-Button Model。
	输出：客户端控制器需要的实例引用；结构不符时直接报合同错误。
	内部算法：BillboardGui 可位于按钮任意后代；其余 UI 使用明确路径。
	不负责：等待场景、触碰、文本计算、Remote 或重生。
]]

local LocalRebirthButtonAccess = {}

local function child(parent: Instance, name: string, className: string): Instance
	local found = parent:FindFirstChild(name)
	assert(
		found and found.ClassName == className,
		string.format("%s 缺少 %s %s", parent:GetFullName(), className, name)
	)
	return found
end

function LocalRebirthButtonAccess.Resolve(button: Model)
	assert(button:IsA("Model"), "Rebirth-Button 必须是 Model")
	local pull = button:FindFirstChild("Pull")
	assert(pull and pull:IsA("BasePart"), "Rebirth-Button 缺少 BasePart Pull")
	local billboard = button:FindFirstChild("BillboardGui", true)
	assert(billboard and billboard:IsA("BillboardGui"), "Rebirth-Button 缺少 BillboardGui")

	local panel = child(billboard, "Panel", "Frame")
	local titleFrame = child(panel, "Title", "Frame")
	local titleLabel = child(titleFrame, "Title", "TextLabel") :: TextLabel
	local rebirthFrame = child(panel, "Rebirth", "Frame")
	local actionButton = child(rebirthFrame, "Button", "TextButton") :: TextButton
	local actionContent = child(actionButton, "Rebirth", "Frame")
	local actionValue = child(actionContent, "Val", "TextLabel") :: TextLabel
	local actionTip = child(actionButton, "Tip", "TextLabel") :: TextLabel

	local buyFrame = child(panel, "Buy", "Frame")
	local infoFrame = child(buyFrame, "Info", "Frame")
	local infoTitle = child(infoFrame, "Title", "TextLabel") :: TextLabel
	local introduction = child(infoFrame, "Introduction", "TextLabel") :: TextLabel
	local moneyFrame = child(infoFrame, "Money", "Frame")
	local moneyButton = child(moneyFrame, "Button", "TextButton") :: TextButton
	local moneyContent = child(moneyButton, "Money", "Frame")
	local requirementValue = child(moneyContent, "Val", "TextLabel") :: TextLabel

	return {
		Pull = pull,
		Billboard = billboard,
		TitleLabel = titleLabel,
		ActionButton = actionButton,
		ActionValue = actionValue,
		ActionTip = actionTip,
		MoneyButton = moneyButton,
		RequirementValue = requirementValue,
		InfoTitle = infoTitle,
		Introduction = introduction,
	}
end

return LocalRebirthButtonAccess
