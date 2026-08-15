--[[
	职责：从 ReplicatedStorage.UI.Rebith 克隆并解析重生按钮的本地 BillboardGui。
	输入：Rebirth-Button Model，以及 ReplicatedStorage.UI.Rebith 模板。
	输出：客户端控制器需要的 Pull、BillboardGui 和新 UI 控件引用；结构不符时直接报合同错误。
	内部算法：关闭按钮模型中旧的 BillboardGui，克隆新模板，再按新 UI 的固定层级解析。
	不负责：等待场景、触碰、文本计算、Remote 或重生。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalRebirthButtonAccess = {}

local function child(parent: Instance, name: string, className: string): Instance
	local found = parent:FindFirstChild(name)
	assert(
		found and found.ClassName == className,
		string.format("%s 缺少 %s %s", parent:GetFullName(), className, name)
	)
	return found
end

local function cloneBillboardTemplate(button: Model): BillboardGui
	for _, descendant in button:GetDescendants() do
		if descendant:IsA("BillboardGui") then
			descendant.Enabled = false
		end
	end

	local uiFolder = ReplicatedStorage:WaitForChild("UI", 10)
	assert(uiFolder and uiFolder:IsA("Folder"), "ReplicatedStorage.UI 必须是 Folder")
	local template = uiFolder:WaitForChild("Rebith", 10)
	assert(template and template:IsA("Attachment"), "ReplicatedStorage.UI.Rebith 必须是 Attachment")
	local billboard = template:FindFirstChild("BillboardGui")
	assert(
		billboard and billboard:IsA("BillboardGui"),
		"ReplicatedStorage.UI.Rebith 缺少 BillboardGui"
	)

	local clone = billboard:Clone()
	clone.Name = "RebirthBillboardGui"
	clone.Enabled = false
	return clone
end

function LocalRebirthButtonAccess.Resolve(button: Model)
	assert(button:IsA("Model"), "Rebirth-Button 必须是 Model")
	local pull = button:FindFirstChild("Pull")
	assert(pull and pull:IsA("BasePart"), "Rebirth-Button 缺少 BasePart Pull")
	local billboard = cloneBillboardTemplate(button)

	local panel = child(billboard, "Panel", "Frame")
	local titleFrame = child(panel, "Title", "Frame")
	local titleLabel = child(titleFrame, "Title", "TextLabel") :: TextLabel

	local buyFrame = child(panel, "Buy", "Frame")
	local infoFrame = child(buyFrame, "Info", "Frame")
	local rebirthFrame = child(infoFrame, "Rebirth", "Frame")
	local actionButton = child(rebirthFrame, "Button", "TextButton") :: TextButton
	local actionContent = child(actionButton, "Rebirth", "Frame")
	local actionValue = child(actionContent, "Val", "TextLabel") :: TextLabel

	local moneyFrame = child(panel, "Money", "Frame")
	local actionTip = child(moneyFrame, "Tip", "TextLabel") :: TextLabel
	local moneyContent = child(moneyFrame, "Money", "Frame")
	local requirementValue = child(moneyContent, "Val", "TextLabel") :: TextLabel

	local buyIcon = buyFrame:FindFirstChild("Icon")
	if buyIcon and not buyIcon:IsA("GuiObject") then
		buyIcon = nil
	end
	local infoTitle = child(infoFrame, "Title", "TextLabel") :: TextLabel
	local introduction = child(infoFrame, "Introduction", "TextLabel") :: TextLabel

	return {
		Pull = pull,
		Billboard = billboard,
		TitleLabel = titleLabel,
		ActionButton = actionButton,
		ActionValue = actionValue,
		ActionTip = actionTip,
		RequirementValue = requirementValue,
		BuyFrame = buyFrame,
		BuyIcon = buyIcon,
		InfoFrame = infoFrame,
		InfoTitle = infoTitle,
		Introduction = introduction,
		RebirthFrame = rebirthFrame,
	}
end

return LocalRebirthButtonAccess
