--[[
	职责：从 ReplicatedStorage.UI.blood 创建一个仅本客户端存在的模型血条。
	输入：目标 Model、局部名称和完整显示快照。
	输出：可 Apply / Destroy 的句柄。
	内部算法：克隆模板到模型 BasePart 顶部，按比例改 bar 宽度并更新动态数字。
	不负责：判断怪兽/房屋是否应显示、读取业务 Attribute 或修改服务器状态。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatHealthBarProtocol = require(
	ReplicatedStorage.Shared.UI.CombatHealthBarProtocol
)
local UIModeVisibilityRules = require(
	ReplicatedStorage.Shared.UI.UIModeVisibilityRules
)
local LocalUIVisibilityGate = require(script.Parent.LocalUIVisibilityGate)

local templateFolder = ReplicatedStorage:WaitForChild(
	CombatHealthBarProtocol.TemplateFolderName
)
local template = templateFolder:WaitForChild(CombatHealthBarProtocol.TemplateName)
assert(template:IsA("Attachment"), "ReplicatedStorage.UI.blood 必须是 Attachment")

local LocalCombatHealthBarUI = {}

export type Handle = {
	Apply: (self: Handle, presentation: any) -> (),
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
	assert(
		child and child.ClassName == className,
		string.format("%s 缺少 %s %s", parent:GetFullName(), className, name)
	)
	return child
end

function LocalCombatHealthBarUI.Create(model: Model, localName: string): Handle
	assert(model:IsA("Model"), "model 必须是 Model")
	assert(type(localName) == "string" and localName ~= "", "localName 必须是非空字符串")

	local parentPart = assert(firstBasePart(model), "战斗血条目标必须至少包含一个 BasePart")
	local attachment = template:Clone()
	attachment.Name = localName

	local billboard = requireChild(attachment, "BillboardGui", "BillboardGui") :: BillboardGui
	local progressBar = requireChild(billboard, "progress bar", "Frame") :: Frame
	local bar = requireChild(progressBar, "bar", "Frame") :: Frame
	local label = requireChild(progressBar, "TextLabel", "TextLabel") :: TextLabel
	local originalBarSize = bar.Size

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

	local function updatePlacement()
		local boundsCFrame, boundsSize = model:GetBoundingBox()
		local worldPosition = boundsCFrame.Position
			+ boundsCFrame.UpVector * (boundsSize.Y * 0.5)
		attachment.CFrame = CFrame.new(parentPart.CFrame:PointToObjectSpace(worldPosition))
	end

	function handle:Apply(presentation)
		if destroyed then
			return
		end
		local enabled = type(presentation) == "table" and presentation.Enabled == true
		visibilityGate:SetDesiredVisible(enabled)
		if not enabled then
			return
		end

		updatePlacement()
		local fillRatio = if type(presentation.FillRatio) == "number"
			then math.clamp(presentation.FillRatio, 0, 1)
			else 0
		bar.Size = UDim2.new(
			fillRatio,
			0,
			originalBarSize.Y.Scale,
			originalBarSize.Y.Offset
		)
		label.Text = if type(presentation.Text) == "string" then presentation.Text else ""
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

return LocalCombatHealthBarUI
