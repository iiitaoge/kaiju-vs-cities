--[[
	职责：稳定包含 Title（可选）、Icon 与 Val 的横向货币信息行。
	输入：带 UIListLayout 的 GuiObject，以及是否包含标题。
	输出：图标与文本使用固定比例槽位，不依赖 TextScaled 和 AutomaticSize 的横向联动。
	内部算法：关闭文本横向自动宽度，限制每个子项的比例尺寸，并裁剪越界内容。
	不负责：设置图标资源、金额文本、业务状态或创建 GUI。
]]

local LocalCurrencyInfoRowLayout = {}

local function configureText(
	target: Instance?,
	widthScale: number,
	textXAlignment: Enum.TextXAlignment
)
	if not target or not target:IsA("TextLabel") and not target:IsA("TextButton") then
		return
	end

	local textTarget = target :: TextLabel | TextButton
	textTarget.AutomaticSize = Enum.AutomaticSize.None
	textTarget.Size = UDim2.fromScale(widthScale, 0.8)
	textTarget.TextSize = 16
	textTarget.TextScaled = true
	textTarget.TextWrapped = false
	textTarget.ClipsDescendants = true
	textTarget.TextXAlignment = textXAlignment
	textTarget.TextYAlignment = Enum.TextYAlignment.Center
end

local function configureIcon(target: Instance?, widthScale: number)
	if not target or not target:IsA("ImageLabel") and not target:IsA("ImageButton") then
		return
	end

	local imageTarget = target :: ImageLabel | ImageButton
	imageTarget.AutomaticSize = Enum.AutomaticSize.None
	imageTarget.Size = UDim2.fromScale(widthScale, 0.8)
end

function LocalCurrencyInfoRowLayout.Configure(
	info: GuiObject,
	hasTitle: boolean,
	leftAlignValue: boolean?
): boolean
	local layout = info:FindFirstChildOfClass("UIListLayout")
	if not layout then
		return false
	end

	info.ClipsDescendants = true
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.01, 0)

	local title = info:FindFirstChild("Title")
	local icon = info:FindFirstChild("Icon")
	local value = info:FindFirstChild("Val")
	local valueAlignment = if leftAlignValue then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	if hasTitle and title and icon and value then
		configureText(title, 0.38, Enum.TextXAlignment.Center)
		configureIcon(icon, 0.16)
		configureText(value, 0.34, valueAlignment)
	elseif icon and value then
		configureIcon(icon, 0.24)
		configureText(value, 0.58, valueAlignment)
	else
		configureText(value, 0.8, valueAlignment)
	end
	return true
end

return table.freeze(LocalCurrencyInfoRowLayout)
