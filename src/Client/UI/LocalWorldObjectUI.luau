--[[
	职责：从共享 Attachment 模板创建一个仅本客户端存在的世界 UI，并应用完整显示快照。
	输入：房屋 Model 顶部或按钮 BasePart，以及显示快照。
	输出：可 Apply / Destroy 的本地句柄。
	内部算法：Clone 模板 → 计算世界锚点到父零件的局部位置 → 严格解析 Text1～Text5/Money。
	不负责：业务查询、收入/HP 计算、按钮 Remote 或选择玩家 Plot。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldObjectUIPlacement = require(
	ReplicatedStorage.Shared.UI.WorldObjectUIPlacement
)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local LocalUIVisibilityGate = require(script.Parent.LocalUIVisibilityGate)

local template = ReplicatedStorage:WaitForChild("WorldObjectUI")
assert(template:IsA("Attachment"), "ReplicatedStorage.WorldObjectUI 必须是 Attachment")

local LocalWorldObjectUI = {}

export type Handle = {
	Apply: (self: Handle, presentation: any?) -> (),
	Destroy: (self: Handle) -> (),
}

local function firstBasePart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function requireChild(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	assert(child and child.ClassName == className, string.format("%s 缺少 %s %s", parent:GetFullName(), className, name))
	return child
end

local function createAt(
	parentPart: BasePart,
	worldPosition: Vector3,
	localName: string
): Handle
	local attachment = template:Clone()
	attachment.Name = localName
	attachment.CFrame = CFrame.new(parentPart.CFrame:PointToObjectSpace(worldPosition))

	local billboard = requireChild(attachment, "BillboardGui", "BillboardGui") :: BillboardGui
	local panel = requireChild(billboard, "Panel", "Frame") :: Frame
	local labels = {}
	for index = 1, 5 do
		local name = "Text" .. tostring(index)
		labels[name] = requireChild(panel, name, "TextLabel") :: TextLabel
	end
	local money = requireChild(panel, "Money", "Frame") :: Frame
	local moneyValue = requireChild(money, "Val", "TextLabel") :: TextLabel

	billboard.Enabled = false
	attachment.Parent = parentPart
	local visibilityGate = LocalUIVisibilityGate.Create(
		UIModeVisibilityRules.Channels.Gameplay,
		function(visible)
			billboard.Enabled = visible
		end,
		false
	)

	local destroyed = false
	local handle = {} :: any

	function handle:Apply(presentation)
		if destroyed then
			return
		end
		local enabled = type(presentation) == "table" and presentation.Enabled == true
		visibilityGate:SetDesiredVisible(enabled)
		if not enabled then
			return
		end

		local texts = presentation.Texts
		for name, label in labels do
			local value = type(texts) == "table" and texts[name] or nil
			label.Visible = type(value) == "table" and value.Visible == true
			label.Text = if type(value) == "table" and type(value.Text) == "string"
				then value.Text
				else ""
		end

		local moneyPresentation = presentation.Money
		money.Visible = type(moneyPresentation) == "table"
			and moneyPresentation.Visible == true
		moneyValue.Text = if type(moneyPresentation) == "table"
			and type(moneyPresentation.Text) == "string"
			then moneyPresentation.Text
			else ""
	end

	function handle:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		visibilityGate:Destroy()
		if attachment.Parent then
			attachment:Destroy()
		end
	end

	return handle
end

function LocalWorldObjectUI.CreateAboveModel(model: Model, localName: string): Handle
	assert(model:IsA("Model"), "model 必须是 Model")
	local parentPart = assert(firstBasePart(model), "世界 UI 房屋必须至少包含一个 BasePart")
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local worldPosition = boundsCFrame.Position
		+ boundsCFrame.UpVector
			* (boundsSize.Y * 0.5 + WorldObjectUIPlacement.HouseTopOffsetStuds)
	return createAt(parentPart, worldPosition, localName)
end

function LocalWorldObjectUI.CreateAbovePart(part: BasePart, localName: string): Handle
	assert(part:IsA("BasePart"), "part 必须是 BasePart")
	local worldPosition = part.Position
		+ part.CFrame.UpVector * WorldObjectUIPlacement.ButtonTopOffsetStuds
	return createAt(part, worldPosition, localName)
end

return LocalWorldObjectUI
